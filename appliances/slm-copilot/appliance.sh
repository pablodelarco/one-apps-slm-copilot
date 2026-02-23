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
via llama-server (llama.cpp). OpenAI-compatible API for Cline/VS Code integration.
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
    'ONEAPP_COPILOT_CONTEXT_SIZE'  'configure' 'Model context window in tokens'          '32768'
    'ONEAPP_COPILOT_THREADS'       'configure' 'CPU threads for inference (0=auto-detect)' '0'
    'ONEAPP_COPILOT_PASSWORD'      'configure' 'API password (auto-generated if empty)'      ''
    'ONEAPP_COPILOT_DOMAIN'        'configure' 'FQDN for Let'\''s Encrypt certificate'       ''
    'ONEAPP_COPILOT_MODEL'         'configure' 'Model: devstral (built-in) or GGUF URL'       'devstral'
)

# --------------------------------------------------------------------------
# Default value assignments
# --------------------------------------------------------------------------
ONEAPP_COPILOT_CONTEXT_SIZE="${ONEAPP_COPILOT_CONTEXT_SIZE:-32768}"
ONEAPP_COPILOT_THREADS="${ONEAPP_COPILOT_THREADS:-0}"
ONEAPP_COPILOT_PASSWORD="${ONEAPP_COPILOT_PASSWORD:-}"
ONEAPP_COPILOT_DOMAIN="${ONEAPP_COPILOT_DOMAIN:-}"
ONEAPP_COPILOT_MODEL="${ONEAPP_COPILOT_MODEL:-devstral}"

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

# Model GGUF filename (Devstral Small 2 24B Instruct Q4_K_M)
readonly MODEL_GGUF="Devstral-Small-2-24B-Instruct-2512-Q4_K_M.gguf"
readonly MODEL_HF_REPO="unsloth/Devstral-Small-2-24B-Instruct-2512-GGUF"

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
#  REPORT: write_report_file  (INI-style report at ONE_SERVICE_REPORT)
# ==========================================================================

# Writes the service report file with connection info, credentials, model
# details, live service status, Cline configuration, and a curl test command.
# Called at the END of service_bootstrap (after services confirmed running).
write_report_file() {
    local _vm_ip
    _vm_ip=$(hostname -I | awk '{print $1}')

    # ALWAYS read password from persisted file
    local _password
    _password=$(cat "${LLAMA_DATA_DIR}/password" 2>/dev/null || echo 'unknown')

    # Determine TLS mode
    local _tls_mode="self-signed"
    if [ -n "${ONEAPP_COPILOT_DOMAIN:-}" ] && \
       [ -f "/etc/letsencrypt/live/${ONEAPP_COPILOT_DOMAIN}/fullchain.pem" ]; then
        _tls_mode="letsencrypt (${ONEAPP_COPILOT_DOMAIN})"
    fi

    # Determine endpoint URL (domain if set, IP otherwise)
    local _endpoint="https://${_vm_ip}:${LLAMA_PORT}"
    if [ -n "${ONEAPP_COPILOT_DOMAIN:-}" ]; then
        _endpoint="https://${ONEAPP_COPILOT_DOMAIN}:${LLAMA_PORT}"
    fi

    # Query live service status
    local _llama_status
    _llama_status=$(systemctl is-active slm-copilot 2>/dev/null || echo unknown)

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
threads      = ${ONEAPP_COPILOT_THREADS}

[Service status]
llama-server = ${_llama_status}
tls          = ${_tls_mode}

[Cline VS Code setup]
1. Install Cline extension in VS Code
2. Click settings gear icon in Cline panel
3. Select "OpenAI Compatible" as API Provider
4. Enter these values:
   Base URL  : ${_endpoint}/v1
   API Key   : ${_password}
   Model ID  : ${ACTIVE_MODEL_ID}

[Cline JSON snippet]
{
  "apiProvider": "openai-compatible",
  "openAiBaseUrl": "${_endpoint}/v1",
  "openAiApiKey": "${_password}",
  "openAiModelId": "${ACTIVE_MODEL_ID}"
}

[Test with curl]
curl -k -H "Authorization: Bearer ${_password}" ${_endpoint}/v1/chat/completions \\
  -H 'Content-Type: application/json' \\
  -d '{"model":"${ACTIVE_MODEL_ID}","messages":[{"role":"user","content":"Hello"}]}'
EOF

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
    local _model_url="https://huggingface.co/${MODEL_HF_REPO}/resolve/main/${MODEL_GGUF}"
    log_copilot info "Downloading ${MODEL_GGUF} from Hugging Face (approx 14 GB)"
    curl -fSL --progress-bar -o "${LLAMA_MODEL_DIR}/${MODEL_GGUF}" "${_model_url}"
    log_copilot info "Model downloaded to ${LLAMA_MODEL_DIR}/${MODEL_GGUF}"

    # 5. Create systemd unit file
    mkdir -p /etc/slm-copilot
    cat > "${LLAMA_SYSTEMD_UNIT}" <<'UNIT_EOF'
[Unit]
Description=SLM-Copilot AI Coding Assistant (llama-server)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/slm-copilot/env
ExecStart=/usr/local/bin/llama-server \
  --host ${LLAMA_HOST} \
  --port ${LLAMA_PORT} \
  --model ${LLAMA_MODEL} \
  --ctx-size ${LLAMA_CTX_SIZE} \
  --threads ${LLAMA_THREADS} \
  --flash-attn on \
  --mlock \
  --metrics \
  --prio 2 \
  --ssl-key-file ${LLAMA_SSL_KEY} \
  --ssl-cert-file ${LLAMA_SSL_CERT} \
  --api-key ${LLAMA_API_KEY}
Restart=on-failure
RestartSec=5
LimitMEMLOCK=infinity
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
UNIT_EOF

    # 6. Verify model file integrity (check file size is reasonable)
    local _model_size
    _model_size=$(stat -c%s "${LLAMA_MODEL_DIR}/${MODEL_GGUF}" 2>/dev/null || echo 0)
    if [ "${_model_size}" -lt 1000000000 ]; then
        log_copilot error "Model file too small (${_model_size} bytes) -- download may be corrupted"
        exit 1
    fi
    log_copilot info "Model file verified ($(( _model_size / 1073741824 )) GB)"

    systemctl daemon-reload

    # 8. Clean up build dependencies to reduce image size
    rm -rf "${_build_dir}"
    apt-get purge -y build-essential cmake libcurl4-openssl-dev >/dev/null 2>&1 || true
    apt-get autoremove -y --purge >/dev/null 2>&1 || true
    apt-get clean -y
    rm -rf /var/lib/apt/lists/*

    # 9. Install SSH login banner
    cat > /etc/profile.d/slm-copilot-banner.sh <<'BANNER_EOF'
#!/bin/bash
[[ $- == *i* ]] || return
_vm_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
_password=$(cat /var/lib/slm-copilot/password 2>/dev/null || echo 'see report')
_llama=$(systemctl is-active slm-copilot 2>/dev/null || echo 'unknown')
_model=$(basename "$(grep '^LLAMA_MODEL=' /etc/slm-copilot/env 2>/dev/null | cut -d= -f2-)" .gguf 2>/dev/null || echo 'unknown')
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

    # 7. Reload systemd to pick up any env file changes
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

    # 1. Attempt Let's Encrypt before starting llama-server (port 80 is free)
    attempt_letsencrypt

    # 2. Enable and start llama-server
    systemctl enable slm-copilot.service
    systemctl start slm-copilot.service

    # 3. Wait for readiness
    wait_for_llama

    # 4. Write report file with connection info, credentials, Cline config
    write_report_file

    log_copilot info "SLM-Copilot bootstrap complete -- llama-server on 0.0.0.0:${LLAMA_PORT}"
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
for Cline/VS Code. Native TLS, Bearer token auth, Prometheus metrics.

Configuration variables (set via OpenNebula context):
  ONEAPP_COPILOT_CONTEXT_SIZE   Model context window in tokens (default: 32768)
                                Valid range: 512-131072 tokens
  ONEAPP_COPILOT_THREADS        CPU threads for inference (default: 0 = auto-detect)
                                Set to number of physical cores for best performance
  ONEAPP_COPILOT_PASSWORD       API key / Bearer token (auto-generated 16-char if empty)
  ONEAPP_COPILOT_DOMAIN         FQDN for Let's Encrypt certificate (optional)
                                If empty, self-signed certificate is used
  ONEAPP_COPILOT_MODEL          Model: 'devstral' (built-in) or a GGUF URL
                                Example URL: https://huggingface.co/bartowski/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf

Ports:
  8443  HTTPS API (TLS + Bearer token auth + Prometheus metrics)

Service management:
  systemctl status slm-copilot        Check inference server status
  systemctl restart slm-copilot       Restart the inference server
  journalctl -u slm-copilot -f        Follow inference server logs

Configuration files:
  /etc/slm-copilot/env                            Environment file (llama-server config)
  /etc/ssl/slm-copilot/cert.pem                   TLS certificate (symlink)
  /etc/ssl/slm-copilot/key.pem                    TLS private key (symlink)
  /opt/models/                                     Model GGUF file(s)

Report and logs:
  /etc/one-appliance/config                    Service report (credentials, Cline config)
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
    local _model="${ONEAPP_COPILOT_MODEL:-devstral}"

    if [ "${_model}" = "devstral" ]; then
        # Built-in model (baked into image at install time)
        ACTIVE_MODEL_PATH="${LLAMA_MODEL_DIR}/${MODEL_GGUF}"
        ACTIVE_MODEL_ID="devstral-small-2"
        log_copilot info "Using built-in model: ${ACTIVE_MODEL_ID}"

        if [ ! -f "${ACTIVE_MODEL_PATH}" ]; then
            log_copilot error "Built-in model not found at ${ACTIVE_MODEL_PATH}"
            exit 1
        fi
        _persist_model_info
        return 0
    fi

    # Treat as a direct GGUF download URL
    if [[ "${_model}" =~ ^https?:// ]]; then
        local _filename
        _filename=$(basename "${_model}" | sed 's/[?#].*//')

        # Validate filename looks like a GGUF
        if [[ ! "${_filename}" =~ \.gguf$ ]]; then
            log_copilot error "ONEAPP_COPILOT_MODEL URL must point to a .gguf file (got: ${_filename})"
            exit 1
        fi

        ACTIVE_MODEL_PATH="${LLAMA_MODEL_DIR}/${_filename}"
        # Derive model ID from filename (strip extension and quant suffix)
        ACTIVE_MODEL_ID=$(echo "${_filename}" | sed 's/\.gguf$//; s/-Q[0-9].*$//' | tr '[:upper:]' '[:lower:]')

        # Skip download if file already exists and is non-trivial size
        if [ -f "${ACTIVE_MODEL_PATH}" ]; then
            local _size
            _size=$(stat -c%s "${ACTIVE_MODEL_PATH}" 2>/dev/null || echo 0)
            if [ "${_size}" -gt 1000000000 ]; then
                log_copilot info "Custom model already downloaded: ${_filename} ($(( _size / 1073741824 )) GB)"
                _persist_model_info
                return 0
            fi
            log_copilot warning "Existing file too small, re-downloading: ${_filename}"
        fi

        log_copilot info "Downloading custom model: ${_model}"
        mkdir -p "${LLAMA_MODEL_DIR}"
        if ! curl -fSL --progress-bar -o "${ACTIVE_MODEL_PATH}" "${_model}"; then
            log_copilot error "Failed to download model from ${_model}"
            rm -f "${ACTIVE_MODEL_PATH}"
            exit 1
        fi

        local _size
        _size=$(stat -c%s "${ACTIVE_MODEL_PATH}" 2>/dev/null || echo 0)
        log_copilot info "Custom model downloaded: ${_filename} ($(( _size / 1073741824 )) GB)"
        _persist_model_info
        return 0
    fi

    log_copilot error "ONEAPP_COPILOT_MODEL='${_model}' -- must be 'devstral' or a direct GGUF URL (https://.../*.gguf)"
    exit 1
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

    # ONEAPP_COPILOT_THREADS: must be a non-negative integer (0 = auto-detect)
    if ! [[ "${ONEAPP_COPILOT_THREADS}" =~ ^[0-9]+$ ]]; then
        log_copilot error "ONEAPP_COPILOT_THREADS='${ONEAPP_COPILOT_THREADS}' -- must be a non-negative integer (0=auto)"
        _errors=$((_errors + 1))
    fi

    # ONEAPP_COPILOT_DOMAIN: if set, must look like a valid FQDN (contains dot, no spaces)
    if [ -n "${ONEAPP_COPILOT_DOMAIN}" ]; then
        if [[ "${ONEAPP_COPILOT_DOMAIN}" =~ [[:space:]] ]] || \
           [[ ! "${ONEAPP_COPILOT_DOMAIN}" =~ \. ]]; then
            log_copilot error "ONEAPP_COPILOT_DOMAIN='${ONEAPP_COPILOT_DOMAIN}' -- must be a valid FQDN (e.g., copilot.example.com)"
            _errors=$((_errors + 1))
        fi
    fi

    # Abort on validation errors
    if [ "${_errors}" -gt 0 ]; then
        log_copilot error "Configuration validation failed with ${_errors} error(s) -- aborting"
        exit 1
    fi

    log_copilot info "Configuration validation passed (context_size=${ONEAPP_COPILOT_CONTEXT_SIZE}, threads=${ONEAPP_COPILOT_THREADS}, domain=${ONEAPP_COPILOT_DOMAIN:-none})"
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
    local _password="${ONEAPP_COPILOT_PASSWORD:-}"

    if [ -z "${_password}" ]; then
        # Preserve existing auto-generated password across reboots
        if [ -f "${LLAMA_DATA_DIR}/password" ]; then
            log_copilot info "Keeping existing auto-generated API key"
            return 0
        fi
        _password=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)
        log_copilot info "Auto-generated API key (no ONEAPP_COPILOT_PASSWORD set)"
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

    local _threads="${ONEAPP_COPILOT_THREADS}"
    if [ "${_threads}" = "0" ]; then
        _threads=$(nproc)
        log_copilot info "Auto-detected ${_threads} CPU threads"
    fi

    mkdir -p /etc/slm-copilot

    cat > "${LLAMA_ENV_FILE}" <<EOF
LLAMA_HOST=0.0.0.0
LLAMA_PORT=${LLAMA_PORT}
LLAMA_MODEL=${ACTIVE_MODEL_PATH}
LLAMA_CTX_SIZE=${ONEAPP_COPILOT_CONTEXT_SIZE}
LLAMA_THREADS=${_threads}
LLAMA_SSL_KEY=${LLAMA_CERT_DIR}/key.pem
LLAMA_SSL_CERT=${LLAMA_CERT_DIR}/cert.pem
LLAMA_API_KEY=${_password}
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
    local _response
    _response=$(curl -sfk "${_endpoint}/v1/chat/completions" \
        -H "Authorization: Bearer ${_api_key}" \
        -H 'Content-Type: application/json' \
        -d '{"model":"devstral-small-2","messages":[{"role":"user","content":"Write a Python hello world"}],"max_tokens":50}') || {
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
        -d '{"model":"devstral-small-2","messages":[{"role":"user","content":"Say hello"}],"max_tokens":10,"stream":true}' \
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
    local _domain="${ONEAPP_COPILOT_DOMAIN:-}"

    if [ -z "${_domain}" ]; then
        log_copilot info "ONEAPP_COPILOT_DOMAIN not set -- using self-signed certificate"
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
HOOK
        chmod +x /etc/letsencrypt/renewal-hooks/deploy/slm-copilot-restart.sh
    else
        log_copilot warning "Let's Encrypt failed for ${_domain} -- keeping self-signed certificate"
        log_copilot warning "Ensure: DNS resolves ${_domain} to this VM, port 80 is reachable from internet"
    fi
}
