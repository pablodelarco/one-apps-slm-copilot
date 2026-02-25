#!/usr/bin/env bash
# --------------------------------------------------------------------------
# SLM-Copilot -- ONE-APPS Appliance Lifecycle Script
#
# Implements the one-apps service_* interface for a sovereign AI coding
# assistant powered by llama-server (llama.cpp) + Devstral Small 2 24B,
# packaged as an OpenNebula marketplace appliance. CPU-only inference with
# native TLS, API key auth, and Prometheus metrics. No GPU required.
# --------------------------------------------------------------------------

# shellcheck disable=SC2034  # ONE_SERVICE_* vars used by one-apps framework

ONE_SERVICE_NAME='Service SLM-Copilot - Sovereign AI Coding Assistant'
ONE_SERVICE_VERSION='2.0.0'
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='CPU-only AI coding copilot (Devstral Small 2 24B via llama.cpp)'
ONE_SERVICE_DESCRIPTION='Sovereign AI coding assistant serving Devstral Small 2 24B
via llama-server (llama.cpp). OpenAI-compatible API for aider, Continue, and more.
Native TLS, API key auth, and Prometheus metrics. CPU-only inference, no GPU required.'
ONE_SERVICE_RECONFIGURABLE=true

# --------------------------------------------------------------------------
# ONE_SERVICE_PARAMS -- flat array, 4-element stride:
#   'VARNAME' 'lifecycle_step' 'Description' 'default_value'
#
# All variables are bound to the 'configure' step so they are re-read on
# every VM boot / reconfigure cycle.
# --------------------------------------------------------------------------
ONE_SERVICE_PARAMS=(
    'ONEAPP_COPILOT_AI_MODEL'         'configure' 'AI model selection'                          'Devstral Small 24B (built-in)'
    'ONEAPP_COPILOT_CONTEXT_SIZE'  'configure' 'Model context window in tokens'              '32768'
    'ONEAPP_COPILOT_API_PASSWORD'       'configure' 'API key / Bearer token (auto-generated if empty)' ''
    'ONEAPP_COPILOT_TLS_DOMAIN'        'configure' 'FQDN for Let'\''s Encrypt certificate'       ''
    'ONEAPP_COPILOT_CPU_THREADS'       'configure' 'CPU threads for inference (0=auto-detect)'   '0'
    'ONEAPP_COPILOT_LB_BACKENDS'       'configure' 'Remote backends for load balancing (empty=standalone)' ''
)

# --------------------------------------------------------------------------
# Default value assignments
# --------------------------------------------------------------------------
ONEAPP_COPILOT_AI_MODEL="${ONEAPP_COPILOT_AI_MODEL:-Devstral Small 24B (built-in)}"
ONEAPP_COPILOT_CONTEXT_SIZE="${ONEAPP_COPILOT_CONTEXT_SIZE:-32768}"
ONEAPP_COPILOT_API_PASSWORD="${ONEAPP_COPILOT_API_PASSWORD:-}"
ONEAPP_COPILOT_TLS_DOMAIN="${ONEAPP_COPILOT_TLS_DOMAIN:-}"
ONEAPP_COPILOT_CPU_THREADS="${ONEAPP_COPILOT_CPU_THREADS:-0}"
ONEAPP_COPILOT_LB_BACKENDS="${ONEAPP_COPILOT_LB_BACKENDS:-}"

# --------------------------------------------------------------------------
# Constants
# --------------------------------------------------------------------------
readonly LLAMA_SERVER_VERSION="b8133"
readonly LLAMA_PORT=8443
readonly LLAMA_CERT_DIR="/etc/ssl/slm-copilot"
readonly LLAMA_DATA_DIR="/var/lib/slm-copilot"
readonly LLAMA_MODEL_DIR="/opt/models"
readonly LLAMA_BIN="/usr/local/bin/llama-server"
readonly LLAMA_SYSTEMD_UNIT="/etc/systemd/system/slm-copilot.service"
readonly LLAMA_ENV_FILE="/etc/slm-copilot/env"
readonly COPILOT_LOG="/var/log/one-appliance/slm-copilot.log"
readonly LITELLM_CONFIG="/etc/slm-copilot/litellm-config.yaml"
readonly LITELLM_SYSTEMD_UNIT="/etc/systemd/system/slm-copilot-proxy.service"
readonly LITELLM_PORT=8443
readonly LLAMA_PORT_LOCAL=8444

# Built-in model (baked into image at install time)
readonly BUILTIN_MODEL_GGUF="Devstral-Small-2-24B-Instruct-2512-Q4_K_M.gguf"
readonly BUILTIN_MODEL_HF_REPO="unsloth/Devstral-Small-2-24B-Instruct-2512-GGUF"

# ---------------------------------------------------------------------------
# Model catalog: name -> "model_id|gguf_filename|hf_url"
# The first entry (Devstral) is baked into the image at build time.
# Others are downloaded on first boot when selected.
# ---------------------------------------------------------------------------
declare -A MODEL_CATALOG=(
    ["Devstral Small 24B (built-in)"]="devstral-small-2|${BUILTIN_MODEL_GGUF}|"
    ["Codestral 22B"]="codestral-22b|Codestral-22B-v0.1-Q4_K_M.gguf|https://huggingface.co/bartowski/Codestral-22B-v0.1-GGUF/resolve/main/Codestral-22B-v0.1-Q4_K_M.gguf"
    ["Mistral Nemo 12B"]="mistral-nemo-12b|Mistral-Nemo-Instruct-2407-Q4_K_M.gguf|https://huggingface.co/bartowski/Mistral-Nemo-Instruct-2407-GGUF/resolve/main/Mistral-Nemo-Instruct-2407-Q4_K_M.gguf"
    ["Codestral Mamba 7B"]="codestral-mamba-7b|codestral-mamba-7B-v0.1-Q4_K_M.gguf|https://huggingface.co/bartowski/Codestral-Mamba-7B-v0.1-GGUF/resolve/main/Codestral-Mamba-7B-v0.1-Q4_K_M.gguf"
    ["Mistral 7B"]="mistral-7b|Mistral-7B-Instruct-v0.3-Q4_K_M.gguf|https://huggingface.co/bartowski/Mistral-7B-Instruct-v0.3-GGUF/resolve/main/Mistral-7B-Instruct-v0.3-Q4_K_M.gguf"
)

# ==========================================================================
#  LOGGING: dedicated application log helpers
# ==========================================================================

# Ensure log directory and file exist with correct permissions
init_copilot_log() {
    mkdir -p /var/log/one-appliance
    touch "${COPILOT_LOG}"
    chmod 0640 "${COPILOT_LOG}"
}

# Log to both the one-apps framework (via msg) and the dedicated log file
log_copilot() {
    local _level="$1"
    shift
    local _message="$*"
    local _timestamp
    _timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "${_timestamp} [${_level^^}] ${_message}" >> "${COPILOT_LOG}"
    msg "${_level}" "${_message}"
}

# ==========================================================================
#  HELPER: is_lb_mode  (true when LiteLLM load balancing is configured)
# ==========================================================================
is_lb_mode() {
    [ -n "${ONEAPP_COPILOT_LB_BACKENDS:-}" ]
}

# ==========================================================================
#  HELPER: get_public_ip  (resolve internet-reachable IP for endpoint)
# ==========================================================================

# Returns the public IP of this VM so that remote users can connect.
# Tries external lookup services first (the VM may be behind NAT),
# falls back to the first local IP if external lookup fails.
get_public_ip() {
    local _pub_ip=""
    for _svc in "https://ifconfig.me" "https://api.ipify.org" "https://icanhazip.com"; do
        _pub_ip=$(curl -sf --max-time 5 "${_svc}" 2>/dev/null | tr -d '[:space:]')
        if [[ "${_pub_ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "${_pub_ip}"
            return 0
        fi
    done
    # Fallback: local IP (private network, may not be reachable from internet)
    hostname -I 2>/dev/null | awk '{print $1}'
}

# ==========================================================================
#  REPORT: write_report_file  (INI-style report at ONE_SERVICE_REPORT)
# ==========================================================================

# Writes the service report file with connection info, credentials, model
# details, live service status, client configuration, and a curl test command.
# Called at the END of service_bootstrap (after services confirmed running).
write_report_file() {
    local _vm_ip
    _vm_ip=$(get_public_ip)

    # ALWAYS read password from persisted file
    local _password
    _password=$(cat "${LLAMA_DATA_DIR}/password" 2>/dev/null || echo 'unknown')

    # Determine TLS mode
    local _tls_mode="self-signed"
    if [ -n "${ONEAPP_COPILOT_TLS_DOMAIN:-}" ] && \
       [ -f "/etc/letsencrypt/live/${ONEAPP_COPILOT_TLS_DOMAIN}/fullchain.pem" ]; then
        _tls_mode="letsencrypt (${ONEAPP_COPILOT_TLS_DOMAIN})"
    fi

    # Determine endpoint URL (domain if set, IP otherwise)
    local _endpoint="https://${_vm_ip}:${LLAMA_PORT}"
    if [ -n "${ONEAPP_COPILOT_TLS_DOMAIN:-}" ]; then
        _endpoint="https://${ONEAPP_COPILOT_TLS_DOMAIN}:${LLAMA_PORT}"
    fi

    # Query live service status
    local _llama_status _proxy_status=""
    _llama_status=$(systemctl is-active slm-copilot 2>/dev/null || echo unknown)
    if is_lb_mode; then
        _proxy_status=$(systemctl is-active slm-copilot-proxy 2>/dev/null || echo unknown)
    fi

    # Write INI-style report to framework-defined path (defensive fallback)
    local _report="${ONE_SERVICE_REPORT:-/etc/one-appliance/config}"
    mkdir -p "$(dirname "${_report}")"

    cat > "${_report}" <<EOF
[Connection info]
endpoint     = ${_endpoint}
api_key      = ${_password}

[Model]
name         = ${ACTIVE_MODEL_ID}
backend      = llama.cpp (llama-server)
model_path   = ${ACTIVE_MODEL_PATH}
context_size = ${ONEAPP_COPILOT_CONTEXT_SIZE}
threads      = ${ONEAPP_COPILOT_CPU_THREADS}

[Service status]
llama-server = ${_llama_status}$(is_lb_mode && printf '\nlitellm-proxy = %s' "${_proxy_status}")
tls          = ${_tls_mode}

[aider setup]
pip install aider-chat

aider --openai-api-key ${_password} \\
      --openai-api-base ${_endpoint}/v1 \\
      --model openai/${ACTIVE_MODEL_ID} \\
      --no-show-model-warnings

[Any OpenAI-compatible client]
Base URL  : ${_endpoint}/v1
API Key   : ${_password}
Model ID  : ${ACTIVE_MODEL_ID}

[Test with curl]
curl -k -H "Authorization: Bearer ${_password}" ${_endpoint}/v1/chat/completions \\
  -H 'Content-Type: application/json' \\
  -d '{"model":"${ACTIVE_MODEL_ID}","messages":[{"role":"user","content":"Hello"}]}'
EOF

    # Append LB section if in load balancer mode
    if is_lb_mode; then
        local _n_remotes
        _n_remotes=$(echo "${ONEAPP_COPILOT_LB_BACKENDS}" | tr ',' '\n' | grep -c '[^[:space:]]')
        cat >> "${_report}" <<EOF

[Load Balancer]
mode            = litellm (least-busy routing)
local_backend   = http://127.0.0.1:${LLAMA_PORT_LOCAL}
remote_backends = ${_n_remotes}
config          = ${LITELLM_CONFIG}
EOF
    fi

    chmod 600 "${_report}"
    log_copilot info "Report file written to ${_report}"
}

# ==========================================================================
#  LIFECYCLE: service_install  (Packer build-time, runs once)
# ==========================================================================
service_install() {
    init_copilot_log
    log_copilot info "=== service_install started ==="
    log_copilot info "Installing SLM-Copilot appliance components (llama-server)"

    # 1. Install build + runtime dependencies
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq build-essential cmake curl jq certbot libcurl4-openssl-dev libssl-dev >/dev/null

    # 2. Clone and compile llama.cpp
    log_copilot info "Cloning llama.cpp at tag ${LLAMA_SERVER_VERSION}"
    local _build_dir="/tmp/llama-cpp-build"
    git clone --depth 1 --branch "${LLAMA_SERVER_VERSION}" \
        https://github.com/ggerganov/llama.cpp.git "${_build_dir}"

    log_copilot info "Compiling llama-server (this may take a while)"
    cmake -S "${_build_dir}" -B "${_build_dir}/build" \
        -DGGML_CPU_ALL_VARIANTS=ON \
        -DGGML_BACKEND_DL=ON \
        -DGGML_BACKEND_DIR=/usr/local/lib \
        -DBUILD_SHARED_LIBS=ON \
        -DLLAMA_CURL=ON \
        -DLLAMA_OPENSSL=ON \
        -DCMAKE_BUILD_TYPE=Release
    cmake --build "${_build_dir}/build" --target llama-server -j"$(nproc)"

    # 3. Install binary and all shared libs (libllama, libggml, libmtmd, CPU backends)
    install -m 0755 "${_build_dir}/build/bin/llama-server" "${LLAMA_BIN}"
    find "${_build_dir}/build" -name "*.so*" -type f -exec cp -a {} /usr/local/lib/ \;
    find "${_build_dir}/build" -name "*.so*" -type l -exec cp -a {} /usr/local/lib/ \;
    ldconfig

    log_copilot info "llama-server installed to ${LLAMA_BIN}"

    # 4. Download Devstral Q4_K_M GGUF from Hugging Face
    mkdir -p "${LLAMA_MODEL_DIR}"
    local _model_url="https://huggingface.co/${BUILTIN_MODEL_HF_REPO}/resolve/main/${BUILTIN_MODEL_GGUF}"
    log_copilot info "Downloading ${BUILTIN_MODEL_GGUF} from Hugging Face (approx 14 GB)"
    curl -fSL --progress-bar -o "${LLAMA_MODEL_DIR}/${BUILTIN_MODEL_GGUF}" "${_model_url}"
    log_copilot info "Model downloaded to ${LLAMA_MODEL_DIR}/${BUILTIN_MODEL_GGUF}"

    # 5. Create wrapper script (handles conditional TLS for standalone vs LB mode)
    mkdir -p /etc/slm-copilot
    cat > /usr/local/bin/slm-copilot-start.sh <<'WRAPPER_EOF'
#!/bin/bash
source /etc/slm-copilot/env
ARGS=(
    --host "${LLAMA_HOST}"
    --port "${LLAMA_PORT}"
    --model "${LLAMA_MODEL}"
    --ctx-size "${LLAMA_CTX_SIZE}"
    --threads "${LLAMA_THREADS}"
    --flash-attn on
    --mlock
    --metrics
    --prio 2
    --api-key "${LLAMA_API_KEY}"
)
[ -n "${LLAMA_SSL_KEY}" ] && ARGS+=(--ssl-key-file "${LLAMA_SSL_KEY}" --ssl-cert-file "${LLAMA_SSL_CERT}")
exec /usr/local/bin/llama-server "${ARGS[@]}"
WRAPPER_EOF
    chmod +x /usr/local/bin/slm-copilot-start.sh

    # 6. Create systemd unit file (delegates to wrapper script)
    cat > "${LLAMA_SYSTEMD_UNIT}" <<'UNIT_EOF'
[Unit]
Description=SLM-Copilot AI Coding Assistant (llama-server)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/slm-copilot-start.sh
Restart=on-failure
RestartSec=5
LimitMEMLOCK=infinity
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
UNIT_EOF

    # 7. Install LiteLLM proxy (optional load balancer, activated by ONEAPP_COPILOT_LB_BACKENDS)
    apt-get install -y -qq python3-pip python3-venv >/dev/null
    python3 -m venv /opt/litellm
    /opt/litellm/bin/pip install 'litellm[proxy]' --quiet
    /opt/litellm/bin/pip cache purge >/dev/null 2>&1 || true

    # Create systemd unit for LiteLLM proxy
    cat > "${LITELLM_SYSTEMD_UNIT}" <<'UNIT_EOF'
[Unit]
Description=SLM-Copilot LiteLLM Load Balancer
After=network-online.target slm-copilot.service
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/slm-copilot/env
ExecStart=/opt/litellm/bin/litellm \
  --config /etc/slm-copilot/litellm-config.yaml \
  --port 8443 \
  --num_workers 2 \
  --ssl_keyfile_path ${SLM_SSL_KEY} \
  --ssl_certfile_path ${SLM_SSL_CERT}
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
UNIT_EOF

    # 8. Verify model file integrity (check file size is reasonable)
    local _model_size
    _model_size=$(stat -c%s "${LLAMA_MODEL_DIR}/${BUILTIN_MODEL_GGUF}" 2>/dev/null || echo 0)
    if [ "${_model_size}" -lt 1000000000 ]; then
        log_copilot error "Model file too small (${_model_size} bytes) -- download may be corrupted"
        exit 1
    fi
    log_copilot info "Model file verified ($(( _model_size / 1073741824 )) GB)"

    systemctl daemon-reload

    # 9. Clean up build dependencies to reduce image size
    rm -rf "${_build_dir}"
    apt-get purge -y build-essential cmake libcurl4-openssl-dev >/dev/null 2>&1 || true
    apt-get autoremove -y --purge >/dev/null 2>&1 || true
    apt-get clean -y
    rm -rf /var/lib/apt/lists/*

    # 10. Install SSH login banner
    cat > /etc/profile.d/slm-copilot-banner.sh <<'BANNER_EOF'
#!/bin/bash
[[ $- == *i* ]] || return
_pub_ip=""
for _svc in "https://ifconfig.me" "https://api.ipify.org" "https://icanhazip.com"; do
    _pub_ip=$(curl -sf --max-time 3 "${_svc}" 2>/dev/null | tr -d '[:space:]')
    [[ "${_pub_ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && break
    _pub_ip=""
done
_vm_ip="${_pub_ip:-$(hostname -I 2>/dev/null | awk '{print $1}')}"
_password=$(cat /var/lib/slm-copilot/password 2>/dev/null || echo 'see report')
_llama=$(systemctl is-active slm-copilot 2>/dev/null || echo 'unknown')
_model=$(cat /var/lib/slm-copilot/model_id 2>/dev/null || echo 'unknown')
printf '\n'
printf '  SLM-Copilot -- Sovereign AI Coding Assistant\n'
printf '  =============================================\n'
printf '  Endpoint : https://%s:8443\n' "${_vm_ip}"
printf '  API Key  : %s\n' "${_password}"
printf '  Model    : %s\n' "${_model}"
printf '  Backend  : llama-server (llama.cpp)\n'
printf '  Status   : %s\n' "${_llama}"
printf '\n'
printf '  Report   : cat /etc/one-appliance/config\n'
printf '  Logs     : tail -f /var/log/one-appliance/slm-copilot.log\n'
printf '\n'
BANNER_EOF
    chmod 0644 /etc/profile.d/slm-copilot-banner.sh

    log_copilot info "SLM-Copilot appliance install complete (llama-server)"
}

# ==========================================================================
#  LIFECYCLE: service_configure  (runs at each VM boot)
# ==========================================================================
service_configure() {
    init_copilot_log
    log_copilot info "=== service_configure started ==="
    log_copilot info "Configuring SLM-Copilot"

    # 1. Validate context variables (fail-fast on invalid values)
    validate_config

    # 2. Check for AVX2 support (warn only, don't fail)
    if ! grep -q avx2 /proc/cpuinfo; then
        log_copilot warning "CPU does not support AVX2 -- llama-server inference may be slow (GGML_CPU_ALL_VARIANTS provides fallback)"
    fi

    # 3. Resolve model (built-in or download custom GGUF)
    resolve_model

    # 4. Generate/persist TLS certificate
    generate_selfsigned_cert

    # 5. Generate/persist API password
    generate_password

    # 6. Write llama-server environment file
    generate_llama_env

    # 7. Generate LiteLLM config if load balancing is enabled
    if is_lb_mode; then
        generate_litellm_config
    fi

    # 8. Reload systemd to pick up any env file changes
    systemctl daemon-reload

    log_copilot info "SLM-Copilot configuration complete"
}

# ==========================================================================
#  LIFECYCLE: service_bootstrap  (runs after configure, starts services)
# ==========================================================================
service_bootstrap() {
    init_copilot_log
    log_copilot info "=== service_bootstrap started ==="
    log_copilot info "Bootstrapping SLM-Copilot"

    # 0. Load model info persisted by service_configure
    _load_model_info

    # 0b. Clean up services from previous mode (handles standalone <-> LB switching)
    if is_lb_mode; then
        # LB mode: llama-server must not be on :8443 from a previous standalone boot
        systemctl stop slm-copilot.service 2>/dev/null || true
    else
        # Standalone mode: disable proxy if it was enabled in a previous LB boot
        systemctl stop slm-copilot-proxy.service 2>/dev/null || true
        systemctl disable slm-copilot-proxy.service 2>/dev/null || true
        # Restart llama-server so it picks up the new env (0.0.0.0:8443 + TLS)
        # Without this, a still-running LB-mode process on 127.0.0.1:8444 makes
        # the later `systemctl start` a no-op, leaving :8443 unserved.
        systemctl stop slm-copilot.service 2>/dev/null || true
    fi

    # 1. Attempt Let's Encrypt before starting llama-server (port 80 is free)
    attempt_letsencrypt

    # 2. Enable and start llama-server
    systemctl enable slm-copilot.service
    systemctl start slm-copilot.service

    # 3. Wait for llama-server readiness (port depends on mode)
    if is_lb_mode; then
        wait_for_llama_local
    else
        wait_for_llama
    fi

    # 4. Start LiteLLM proxy if in LB mode
    if is_lb_mode; then
        systemctl enable slm-copilot-proxy.service
        systemctl start slm-copilot-proxy.service
        wait_for_litellm
    fi

    # 5. Write report file with connection info, credentials, client config
    write_report_file

    if is_lb_mode; then
        log_copilot info "SLM-Copilot bootstrap complete -- LiteLLM proxy on 0.0.0.0:${LITELLM_PORT}, llama-server on 127.0.0.1:${LLAMA_PORT_LOCAL}"
    else
        log_copilot info "SLM-Copilot bootstrap complete -- llama-server on 0.0.0.0:${LLAMA_PORT}"
    fi
}

# ==========================================================================
#  LIFECYCLE: service_cleanup
# ==========================================================================
service_cleanup() {
    # No-op: the one-appliance framework calls cleanup between lifecycle stages,
    # but we must not destroy the service that bootstrap just started.
    # Service lifecycle is managed by systemd (Restart=on-failure).
    :
}

# ==========================================================================
#  LIFECYCLE: service_help
# ==========================================================================
service_help() {
    cat <<'HELP'
SLM-Copilot Appliance
=====================

Sovereign AI coding assistant powered by llama-server (llama.cpp) serving
Devstral Small 2 24B (Q4_K_M quantization) on CPU. OpenAI-compatible API
for aider and other OpenAI clients. Native TLS, Bearer token auth, Prometheus metrics.

Configuration variables (set via OpenNebula context):
  ONEAPP_COPILOT_AI_MODEL          AI model from catalog (default: Devstral Small 24B)
                                Available: Devstral 24B, Codestral 22B, Mistral Nemo 12B,
                                Codestral Mamba 7B, Mistral 7B
  ONEAPP_COPILOT_CONTEXT_SIZE   Model context window in tokens (default: 32768)
                                Valid range: 512-131072 tokens
  ONEAPP_COPILOT_API_PASSWORD        API key / Bearer token (auto-generated 16-char if empty)
  ONEAPP_COPILOT_TLS_DOMAIN         FQDN for Let's Encrypt certificate (optional)
                                If empty, self-signed certificate is used
  ONEAPP_COPILOT_CPU_THREADS        CPU threads for inference (default: 0 = auto-detect)
                                Set to number of physical cores for best performance
  ONEAPP_COPILOT_LB_BACKENDS        Remote backends for load balancing (default: empty)
                                Format: key@host:port,key@host:port (empty = standalone)
                                Activates LiteLLM proxy on :8443, llama-server moves to :8444

Ports:
  8443  HTTPS API (TLS + Bearer token auth + Prometheus metrics)

Service management:
  systemctl status slm-copilot        Check inference server status
  systemctl restart slm-copilot       Restart the inference server
  journalctl -u slm-copilot -f        Follow inference server logs
  systemctl status slm-copilot-proxy  Check LiteLLM proxy (LB mode only)
  journalctl -u slm-copilot-proxy -f  Follow proxy logs (LB mode only)

Configuration files:
  /etc/slm-copilot/env                            Environment file (llama-server config)
  /etc/ssl/slm-copilot/cert.pem                   TLS certificate (symlink)
  /etc/ssl/slm-copilot/key.pem                    TLS private key (symlink)
  /opt/models/                                     Model GGUF file(s)
  /etc/slm-copilot/litellm-config.yaml             LiteLLM config (LB mode only)

Report and logs:
  /etc/one-appliance/config                    Service report (credentials, client config)
  /var/log/one-appliance/slm-copilot.log       Application log (all stages)

Health check:
  curl -k https://localhost:8443/health

Prometheus metrics:
  curl -k https://localhost:8443/metrics

Test inference:
  curl -k -H "Authorization: Bearer PASSWORD" https://localhost:8443/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -d '{"model":"devstral-small-2","messages":[{"role":"user","content":"Hello"}]}'

Password retrieval:
  cat /var/lib/slm-copilot/password
HELP
}

# ==========================================================================
#  HELPER: resolve_model  (determine model GGUF path, download if URL)
# ==========================================================================

# Globals set by resolve_model(), consumed by generate_llama_env/write_report
ACTIVE_MODEL_PATH=""
ACTIVE_MODEL_ID=""

resolve_model() {
    local _selection="${ONEAPP_COPILOT_AI_MODEL:-Devstral Small 24B (built-in)}"

    # Look up the selection in the catalog
    local _entry="${MODEL_CATALOG[${_selection}]:-}"

    if [ -z "${_entry}" ]; then
        log_copilot error "Unknown model '${_selection}'. Available: ${!MODEL_CATALOG[*]}"
        exit 1
    fi

    # Parse catalog entry: "model_id|gguf_filename|hf_url"
    ACTIVE_MODEL_ID=$(echo "${_entry}" | cut -d'|' -f1)
    local _gguf_file
    _gguf_file=$(echo "${_entry}" | cut -d'|' -f2)
    local _hf_url
    _hf_url=$(echo "${_entry}" | cut -d'|' -f3)

    ACTIVE_MODEL_PATH="${LLAMA_MODEL_DIR}/${_gguf_file}"

    # Check if model file already exists on disk (built-in or previously downloaded)
    if [ -f "${ACTIVE_MODEL_PATH}" ]; then
        local _size
        _size=$(stat -c%s "${ACTIVE_MODEL_PATH}" 2>/dev/null || echo 0)
        if [ "${_size}" -gt 1000000000 ]; then
            log_copilot info "Model ready: ${ACTIVE_MODEL_ID} ($(( _size / 1073741824 )) GB)"
            _persist_model_info
            return 0
        fi
        log_copilot warning "Model file incomplete, re-downloading: ${_gguf_file}"
    fi

    # No local file: download from HuggingFace
    if [ -z "${_hf_url}" ]; then
        log_copilot error "Built-in model file missing at ${ACTIVE_MODEL_PATH}"
        exit 1
    fi

    log_copilot info "Downloading ${ACTIVE_MODEL_ID} from HuggingFace..."
    mkdir -p "${LLAMA_MODEL_DIR}"
    if ! curl -fSL --progress-bar -o "${ACTIVE_MODEL_PATH}" "${_hf_url}"; then
        log_copilot error "Failed to download model from ${_hf_url}"
        rm -f "${ACTIVE_MODEL_PATH}"
        exit 1
    fi

    local _size
    _size=$(stat -c%s "${ACTIVE_MODEL_PATH}" 2>/dev/null || echo 0)
    log_copilot info "Model downloaded: ${ACTIVE_MODEL_ID} ($(( _size / 1073741824 )) GB)"
    _persist_model_info
}

# Persist resolved model path/ID so service_bootstrap can read them
_persist_model_info() {
    mkdir -p "${LLAMA_DATA_DIR}"
    echo "${ACTIVE_MODEL_PATH}" > "${LLAMA_DATA_DIR}/model_path"
    echo "${ACTIVE_MODEL_ID}" > "${LLAMA_DATA_DIR}/model_id"
}

# Load persisted model path/ID (for service_bootstrap, which runs in a separate stage)
_load_model_info() {
    ACTIVE_MODEL_PATH=$(cat "${LLAMA_DATA_DIR}/model_path" 2>/dev/null || echo "${LLAMA_MODEL_DIR}/${MODEL_GGUF}")
    ACTIVE_MODEL_ID=$(cat "${LLAMA_DATA_DIR}/model_id" 2>/dev/null || echo "devstral-small-2")
}

# ==========================================================================
#  HELPER: validate_config  (fail-fast on invalid context variable values)
# ==========================================================================
validate_config() {
    local _errors=0

    # ONEAPP_COPILOT_CONTEXT_SIZE: must be a positive integer, reasonable range 512-131072
    if ! [[ "${ONEAPP_COPILOT_CONTEXT_SIZE}" =~ ^[1-9][0-9]*$ ]]; then
        log_copilot error "ONEAPP_COPILOT_CONTEXT_SIZE='${ONEAPP_COPILOT_CONTEXT_SIZE}' -- must be a positive integer"
        _errors=$((_errors + 1))
    elif [ "${ONEAPP_COPILOT_CONTEXT_SIZE}" -lt 512 ]; then
        log_copilot error "ONEAPP_COPILOT_CONTEXT_SIZE='${ONEAPP_COPILOT_CONTEXT_SIZE}' -- minimum 512 tokens"
        _errors=$((_errors + 1))
    elif [ "${ONEAPP_COPILOT_CONTEXT_SIZE}" -gt 131072 ]; then
        log_copilot warning "ONEAPP_COPILOT_CONTEXT_SIZE='${ONEAPP_COPILOT_CONTEXT_SIZE}' -- very large context, may cause OOM on 32 GB VM"
    fi

    # ONEAPP_COPILOT_CPU_THREADS: must be a non-negative integer (0 = auto-detect)
    if ! [[ "${ONEAPP_COPILOT_CPU_THREADS}" =~ ^[0-9]+$ ]]; then
        log_copilot error "ONEAPP_COPILOT_CPU_THREADS='${ONEAPP_COPILOT_CPU_THREADS}' -- must be a non-negative integer (0=auto)"
        _errors=$((_errors + 1))
    fi

    # ONEAPP_COPILOT_TLS_DOMAIN: if set, must look like a valid FQDN (contains dot, no spaces)
    if [ -n "${ONEAPP_COPILOT_TLS_DOMAIN}" ]; then
        if [[ "${ONEAPP_COPILOT_TLS_DOMAIN}" =~ [[:space:]] ]] || \
           [[ ! "${ONEAPP_COPILOT_TLS_DOMAIN}" =~ \. ]]; then
            log_copilot error "ONEAPP_COPILOT_TLS_DOMAIN='${ONEAPP_COPILOT_TLS_DOMAIN}' -- must be a valid FQDN (e.g., copilot.example.com)"
            _errors=$((_errors + 1))
        fi
    fi

    # Abort on validation errors
    if [ "${_errors}" -gt 0 ]; then
        log_copilot error "Configuration validation failed with ${_errors} error(s) -- aborting"
        exit 1
    fi

    log_copilot info "Configuration validation passed (context_size=${ONEAPP_COPILOT_CONTEXT_SIZE}, threads=${ONEAPP_COPILOT_CPU_THREADS}, domain=${ONEAPP_COPILOT_TLS_DOMAIN:-none})"
}

# ==========================================================================
#  HELPER: generate_selfsigned_cert  (self-signed X.509 with VM IP SAN)
# ==========================================================================
generate_selfsigned_cert() {
    local _vm_ip
    _vm_ip=$(hostname -I | awk '{print $1}')

    mkdir -p "${LLAMA_CERT_DIR}"

    openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout "${LLAMA_CERT_DIR}/selfsigned-key.pem" \
        -out "${LLAMA_CERT_DIR}/selfsigned-cert.pem" \
        -days 3650 \
        -subj "/CN=SLM-Copilot" \
        -addext "subjectAltName=DNS:localhost,IP:127.0.0.1,IP:${_vm_ip}"

    chmod 0600 "${LLAMA_CERT_DIR}/selfsigned-key.pem"
    chmod 0644 "${LLAMA_CERT_DIR}/selfsigned-cert.pem"

    # Active cert symlinks (Let's Encrypt replaces these if domain is set)
    ln -sf "${LLAMA_CERT_DIR}/selfsigned-cert.pem" "${LLAMA_CERT_DIR}/cert.pem"
    ln -sf "${LLAMA_CERT_DIR}/selfsigned-key.pem" "${LLAMA_CERT_DIR}/key.pem"

    log_copilot info "Self-signed certificate generated for ${_vm_ip}"
}

# ==========================================================================
#  HELPER: generate_password  (auto-generate or persist user-provided)
# ==========================================================================
generate_password() {
    local _password="${ONEAPP_COPILOT_API_PASSWORD:-}"

    if [ -z "${_password}" ]; then
        # Preserve existing auto-generated password across reboots
        if [ -f "${LLAMA_DATA_DIR}/password" ]; then
            log_copilot info "Keeping existing auto-generated API key"
            return 0
        fi
        _password=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)
        log_copilot info "Auto-generated API key (no ONEAPP_COPILOT_API_PASSWORD set)"
    fi

    mkdir -p "${LLAMA_DATA_DIR}"
    echo "${_password}" > "${LLAMA_DATA_DIR}/password"
    chmod 0600 "${LLAMA_DATA_DIR}/password"

    log_copilot info "API key persisted to ${LLAMA_DATA_DIR}/password"
}

# ==========================================================================
#  HELPER: generate_llama_env  (write systemd environment file)
# ==========================================================================
generate_llama_env() {
    local _password
    _password=$(cat "${LLAMA_DATA_DIR}/password" 2>/dev/null || echo 'changeme')

    local _threads="${ONEAPP_COPILOT_CPU_THREADS}"
    if [ "${_threads}" = "0" ]; then
        _threads=$(nproc)
        log_copilot info "Auto-detected ${_threads} CPU threads"
    fi

    local _host="0.0.0.0"
    local _port="${LLAMA_PORT}"
    local _ssl_key="${LLAMA_CERT_DIR}/key.pem"
    local _ssl_cert="${LLAMA_CERT_DIR}/cert.pem"

    if is_lb_mode; then
        _host="127.0.0.1"
        _port="${LLAMA_PORT_LOCAL}"
        _ssl_key=""
        _ssl_cert=""
        log_copilot info "LB mode: llama-server on 127.0.0.1:${LLAMA_PORT_LOCAL} (no TLS)"
    fi

    mkdir -p /etc/slm-copilot

    cat > "${LLAMA_ENV_FILE}" <<EOF
LLAMA_HOST=${_host}
LLAMA_PORT=${_port}
LLAMA_MODEL=${ACTIVE_MODEL_PATH}
LLAMA_CTX_SIZE=${ONEAPP_COPILOT_CONTEXT_SIZE}
LLAMA_THREADS=${_threads}
LLAMA_SSL_KEY=${_ssl_key}
LLAMA_SSL_CERT=${_ssl_cert}
LLAMA_API_KEY=${_password}
SLM_SSL_KEY=${LLAMA_CERT_DIR}/key.pem
SLM_SSL_CERT=${LLAMA_CERT_DIR}/cert.pem
EOF
    chmod 0600 "${LLAMA_ENV_FILE}"

    log_copilot info "Environment file written to ${LLAMA_ENV_FILE} (ctx_size=${ONEAPP_COPILOT_CONTEXT_SIZE}, threads=${_threads})"
}

# ==========================================================================
#  HELPER: wait_for_llama  (poll health endpoint, 300s timeout)
# ==========================================================================
wait_for_llama() {
    local _timeout=300
    local _elapsed=0
    log_copilot info "Waiting for llama-server readiness (timeout: ${_timeout}s)"
    while ! curl -sfk "https://127.0.0.1:${LLAMA_PORT}/health" >/dev/null 2>&1; do
        sleep 5
        _elapsed=$((_elapsed + 5))
        if [ "${_elapsed}" -ge "${_timeout}" ]; then
            log_copilot error "llama-server not ready after ${_timeout}s -- check: journalctl -u slm-copilot"
            exit 1
        fi
    done
    log_copilot info "llama-server ready (${_elapsed}s)"
}

# ==========================================================================
#  HELPER: wait_for_llama_local  (poll HTTP health, LB mode only)
# ==========================================================================
wait_for_llama_local() {
    local _timeout=300 _elapsed=0
    log_copilot info "Waiting for local llama-server on :${LLAMA_PORT_LOCAL}"
    while ! curl -sf "http://127.0.0.1:${LLAMA_PORT_LOCAL}/health" >/dev/null 2>&1; do
        sleep 5
        _elapsed=$((_elapsed + 5))
        if [ "${_elapsed}" -ge "${_timeout}" ]; then
            log_copilot error "llama-server not ready after ${_timeout}s"
            exit 1
        fi
    done
    log_copilot info "Local llama-server ready (${_elapsed}s)"
}

# ==========================================================================
#  HELPER: wait_for_litellm  (poll HTTPS health, LB mode only)
# ==========================================================================
wait_for_litellm() {
    local _timeout=60 _elapsed=0
    log_copilot info "Waiting for LiteLLM proxy on :${LITELLM_PORT}"
    while ! curl -sfk "https://127.0.0.1:${LITELLM_PORT}/health/liveliness" >/dev/null 2>&1; do
        sleep 3
        _elapsed=$((_elapsed + 3))
        if [ "${_elapsed}" -ge "${_timeout}" ]; then
            log_copilot error "LiteLLM proxy not ready after ${_timeout}s"
            exit 1
        fi
    done
    log_copilot info "LiteLLM proxy ready (${_elapsed}s)"
}

# ==========================================================================
#  HELPER: generate_litellm_config  (LiteLLM YAML for load balancing)
# ==========================================================================
generate_litellm_config() {
    local _local_password
    _local_password=$(cat "${LLAMA_DATA_DIR}/password" 2>/dev/null || echo 'changeme')

    # Start config with local backend (always included)
    cat > "${LITELLM_CONFIG}" <<EOF
model_list:
  - model_name: "${ACTIVE_MODEL_ID}"
    litellm_params:
      model: "openai/${ACTIVE_MODEL_ID}"
      api_base: "http://127.0.0.1:${LLAMA_PORT_LOCAL}/v1"
      api_key: "${_local_password}"
EOF

    # Parse remote backends: "key@host:port,key@host:port" or "host:port,host:port"
    local _backends="${ONEAPP_COPILOT_LB_BACKENDS}"
    local _entries _entry _key _url _i=0
    IFS=',' read -ra _entries <<< "${_backends}"
    for _entry in "${_entries[@]}"; do
        _entry=$(echo "${_entry}" | xargs)  # trim whitespace
        [ -z "${_entry}" ] && continue

        _key="${_local_password}"
        _url="${_entry}"
        if [[ "${_entry}" == *@* ]]; then
            _key="${_entry%%@*}"
            _url="${_entry#*@}"
        fi
        # Ensure URL has scheme
        if [[ "${_url}" != https://* ]] && [[ "${_url}" != http://* ]]; then
            _url="https://${_url}"
        fi

        cat >> "${LITELLM_CONFIG}" <<EOF
  - model_name: "${ACTIVE_MODEL_ID}"
    litellm_params:
      model: "openai/${ACTIVE_MODEL_ID}"
      api_base: "${_url}/v1"
      api_key: "${_key}"
EOF
        _i=$((_i + 1))
    done

    # Append router and general settings
    cat >> "${LITELLM_CONFIG}" <<EOF

router_settings:
  routing_strategy: "least-busy"
  allowed_fails: 2
  cooldown_time: 30

litellm_settings:
  ssl_verify: false

general_settings:
  master_key: "${_local_password}"
EOF

    chmod 0600 "${LITELLM_CONFIG}"
    log_copilot info "LiteLLM config generated: 1 local + ${_i} remote backend(s)"
}

# ==========================================================================
#  HELPER: smoke_test  (verify chat completions, streaming, and health)
# ==========================================================================
smoke_test() {
    local _endpoint="${1:-https://127.0.0.1:${LLAMA_PORT}}"
    local _api_key="${2:-$(cat "${LLAMA_DATA_DIR}/password" 2>/dev/null || echo 'changeme')}"

    log_copilot info "Running smoke test against ${_endpoint}"

    # Test 1: Health endpoint
    curl -sfk "${_endpoint}/health" >/dev/null 2>&1 || {
        log_copilot error "Smoke test: health check (/health) did not return 200"
        return 1
    }
    log_copilot info "Smoke test: health check OK"

    # Test 2: Non-streaming chat completion
    local _model_id
    _model_id=$(cat "${LLAMA_DATA_DIR}/model_id" 2>/dev/null || echo "devstral-small-2")
    local _response
    _response=$(curl -sfk "${_endpoint}/v1/chat/completions" \
        -H "Authorization: Bearer ${_api_key}" \
        -H 'Content-Type: application/json' \
        -d "{\"model\":\"${_model_id}\",\"messages\":[{\"role\":\"user\",\"content\":\"Write a Python hello world\"}],\"max_tokens\":50}") || {
        log_copilot error "Smoke test: chat completion request failed"
        return 1
    }
    echo "${_response}" | jq -e '.choices[0].message.content' >/dev/null 2>&1 || {
        log_copilot error "Smoke test: no content in chat completion response"
        return 1
    }
    log_copilot info "Smoke test: chat completion OK"

    # Test 3: Streaming chat completion
    curl -sfk "${_endpoint}/v1/chat/completions" \
        -H "Authorization: Bearer ${_api_key}" \
        -H 'Content-Type: application/json' \
        -d "{\"model\":\"${_model_id}\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hello\"}],\"max_tokens\":10,\"stream\":true}" \
        | grep -q 'data:' || {
        log_copilot error "Smoke test: streaming response has no SSE data lines"
        return 1
    }
    log_copilot info "Smoke test: streaming OK"

    log_copilot info "All smoke tests passed"
    return 0
}

# ==========================================================================
#  HELPER: attempt_letsencrypt  (certbot standalone, port 80 is free)
# ==========================================================================
attempt_letsencrypt() {
    local _domain="${ONEAPP_COPILOT_TLS_DOMAIN:-}"

    if [ -z "${_domain}" ]; then
        log_copilot info "ONEAPP_COPILOT_TLS_DOMAIN not set -- using self-signed certificate"
        return 0
    fi

    log_copilot info "Attempting Let's Encrypt certificate for ${_domain}"

    # Port 80 is free (no nginx), use certbot standalone
    if certbot certonly \
        --non-interactive \
        --agree-tos \
        --register-unsafely-without-email \
        --standalone \
        --preferred-challenges http \
        -d "${_domain}" 2>&1; then

        # Success: switch active symlinks to Let's Encrypt certs
        ln -sf "/etc/letsencrypt/live/${_domain}/fullchain.pem" "${LLAMA_CERT_DIR}/cert.pem"
        ln -sf "/etc/letsencrypt/live/${_domain}/privkey.pem" "${LLAMA_CERT_DIR}/key.pem"
        log_copilot info "Let's Encrypt certificate installed for ${_domain}"

        # Set up renewal cron (restart llama-server to pick up new certs)
        mkdir -p /etc/letsencrypt/renewal-hooks/deploy
        cat > /etc/letsencrypt/renewal-hooks/deploy/slm-copilot-restart.sh <<'HOOK'
#!/bin/bash
systemctl restart slm-copilot
# Also restart LiteLLM proxy if active (LB mode uses TLS on the proxy)
systemctl is-active --quiet slm-copilot-proxy && systemctl restart slm-copilot-proxy
HOOK
        chmod +x /etc/letsencrypt/renewal-hooks/deploy/slm-copilot-restart.sh
    else
        log_copilot warning "Let's Encrypt failed for ${_domain} -- keeping self-signed certificate"
        log_copilot warning "Ensure: DNS resolves ${_domain} to this VM, port 80 is reachable from internet"
    fi
}
