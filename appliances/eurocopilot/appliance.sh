#!/usr/bin/env bash
# --------------------------------------------------------------------------
# EuroCopilot -- ONE-APPS Appliance Lifecycle Script
#
# Implements the one-apps service_* interface for a sovereign AI coding
# assistant powered by llama-server (llama.cpp) + Devstral Small 2 24B,
# packaged as an OpenNebula marketplace appliance. CPU-only inference with
# native TLS, API key auth, and Prometheus metrics. No GPU required.
# --------------------------------------------------------------------------

# shellcheck disable=SC2034  # ONE_SERVICE_* vars used by one-apps framework

ONE_SERVICE_NAME='Service EuroCopilot - Sovereign AI Coding Assistant'
ONE_SERVICE_VERSION='2.0.0'
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='CPU-only AI coding copilot (Devstral Small 2 24B via llama.cpp)'
ONE_SERVICE_DESCRIPTION='Sovereign AI coding assistant serving Devstral Small 2 24B
via llama-server (llama.cpp). OpenAI-compatible API for aider and any OpenAI client.
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
    'ONEAPP_COPILOT_AI_MODEL'         'configure' 'AI model selection'                          'Devstral Small 2 (24B ~14GB built-in)'
    'ONEAPP_COPILOT_CONTEXT_SIZE'  'configure' 'Model context window in tokens'              '32768'
    'ONEAPP_COPILOT_API_PASSWORD'       'configure' 'API key / Bearer token (auto-generated if empty)' ''
    'ONEAPP_COPILOT_TLS_DOMAIN'        'configure' 'FQDN for Let'\''s Encrypt certificate'       ''
    'ONEAPP_COPILOT_CPU_THREADS'       'configure' 'CPU threads for inference (0=auto-detect)'   '0'
    'ONEAPP_COPILOT_LB_ENABLED'        'configure' 'Enable LiteLLM load balancer mode'                     'NO'
    'ONEAPP_COPILOT_LB_BACKENDS'       'configure' 'Remote backends for load balancing'                    ''
    'ONEAPP_COPILOT_REGISTER_URL'            'configure' 'Remote LB URL for auto-registration'                  ''
    'ONEAPP_COPILOT_REGISTER_KEY'     'configure' 'Remote LB master key for auto-registration'           ''
    'ONEAPP_COPILOT_REGISTER_MODEL_NAME' 'configure' 'Model name override for LB registration'           ''
    'ONEAPP_COPILOT_REGISTER_SITE_NAME'  'configure' 'Site name for LB backend ID (e.g. poland0)'        ''
)

# --------------------------------------------------------------------------
# Default value assignments
# --------------------------------------------------------------------------
ONEAPP_COPILOT_AI_MODEL="${ONEAPP_COPILOT_AI_MODEL:-Devstral Small 2 (24B ~14GB built-in)}"
ONEAPP_COPILOT_CONTEXT_SIZE="${ONEAPP_COPILOT_CONTEXT_SIZE:-32768}"
ONEAPP_COPILOT_API_PASSWORD="${ONEAPP_COPILOT_API_PASSWORD:-}"
ONEAPP_COPILOT_TLS_DOMAIN="${ONEAPP_COPILOT_TLS_DOMAIN:-}"
ONEAPP_COPILOT_CPU_THREADS="${ONEAPP_COPILOT_CPU_THREADS:-0}"
ONEAPP_COPILOT_LB_ENABLED="${ONEAPP_COPILOT_LB_ENABLED:-NO}"
ONEAPP_COPILOT_LB_BACKENDS="${ONEAPP_COPILOT_LB_BACKENDS:-}"
ONEAPP_COPILOT_REGISTER_URL="${ONEAPP_COPILOT_REGISTER_URL:-}"
ONEAPP_COPILOT_REGISTER_KEY="${ONEAPP_COPILOT_REGISTER_KEY:-}"
ONEAPP_COPILOT_REGISTER_MODEL_NAME="${ONEAPP_COPILOT_REGISTER_MODEL_NAME:-}"
ONEAPP_COPILOT_REGISTER_SITE_NAME="${ONEAPP_COPILOT_REGISTER_SITE_NAME:-}"

# --------------------------------------------------------------------------
# Constants
# --------------------------------------------------------------------------
readonly LLAMA_SERVER_VERSION="b8133"
readonly LLAMA_PORT=8443
readonly LLAMA_CERT_DIR="/etc/ssl/eurocopilot"
readonly LLAMA_DATA_DIR="/var/lib/eurocopilot"
readonly LLAMA_MODEL_DIR="/opt/models"
readonly LLAMA_BIN="/usr/local/bin/llama-server"
readonly LLAMA_SYSTEMD_UNIT="/etc/systemd/system/eurocopilot.service"
readonly LLAMA_ENV_FILE="/etc/eurocopilot/env"
readonly COPILOT_LOG="/var/log/one-appliance/eurocopilot.log"
readonly LITELLM_CONFIG="/etc/eurocopilot/litellm-config.yaml"
readonly LITELLM_SYSTEMD_UNIT="/etc/systemd/system/eurocopilot-proxy.service"
readonly LITELLM_PORT=8443
readonly LLAMA_PORT_LOCAL=8444
readonly LB_MODEL_ID_FILE="/etc/eurocopilot/lb_model_id"
readonly LB_DEREGISTER_SCRIPT="/usr/local/bin/eurocopilot-lb-deregister"
readonly LB_DEREGISTER_UNIT="/etc/systemd/system/eurocopilot-lb-deregister.service"
readonly LB_HEALTHCHECK_SCRIPT="/usr/local/bin/eurocopilot-lb-healthcheck"
readonly LB_HEALTHCHECK_UNIT="/etc/systemd/system/eurocopilot-lb-healthcheck.service"
readonly LB_HEALTHCHECK_TIMER="/etc/systemd/system/eurocopilot-lb-healthcheck.timer"

# Built-in model (baked into image at install time)
readonly BUILTIN_MODEL_GGUF="Devstral-Small-2-24B-Instruct-2512-Q4_K_M.gguf"
readonly BUILTIN_MODEL_HF_REPO="unsloth/Devstral-Small-2-24B-Instruct-2512-GGUF"

# ---------------------------------------------------------------------------
# Model catalog: name -> "model_id|gguf_filename|hf_url"
# The first entry (Devstral) is baked into the image at build time.
# Others are downloaded on first boot when selected.
# ---------------------------------------------------------------------------
declare -A MODEL_CATALOG=(
    ["Devstral Small 2 (24B ~14GB built-in)"]="devstral-small-2|${BUILTIN_MODEL_GGUF}|"
    ["Mistral Small Instruct (24B ~14GB)"]="mistral-small-24b|Mistral-Small-24B-Instruct-2501-Q4_K_M.gguf|https://huggingface.co/bartowski/Mistral-Small-24B-Instruct-2501-GGUF/resolve/main/Mistral-Small-24B-Instruct-2501-Q4_K_M.gguf"
    ["Mistral Nemo Instruct (12B ~7GB)"]="mistral-nemo-12b|Mistral-Nemo-Instruct-2407-Q4_K_M.gguf|https://huggingface.co/bartowski/Mistral-Nemo-Instruct-2407-GGUF/resolve/main/Mistral-Nemo-Instruct-2407-Q4_K_M.gguf"
    ["Mistral 7B Instruct (7B ~4GB)"]="mistral-7b|Mistral-7B-Instruct-v0.3-Q4_K_M.gguf|https://huggingface.co/bartowski/Mistral-7B-Instruct-v0.3-GGUF/resolve/main/Mistral-7B-Instruct-v0.3-Q4_K_M.gguf"
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
    [[ "${ONEAPP_COPILOT_LB_ENABLED:-NO}" =~ ^(YES|yes|true|1)$ ]]
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
    _llama_status=$(systemctl is-active eurocopilot 2>/dev/null || echo unknown)
    if is_lb_mode; then
        _proxy_status=$(systemctl is-active eurocopilot-proxy 2>/dev/null || echo unknown)
    fi

    # Write INI-style report to framework-defined path (defensive fallback)
    local _report="${ONE_SERVICE_REPORT:-/etc/one-appliance/config}"
    mkdir -p "$(dirname "${_report}")"

    cat > "${_report}" <<EOF
[Connection info]
endpoint    = ${_endpoint}
api_key     = ${_password}
model       = ${ACTIVE_MODEL_ID}

[Web UI]
Open ${_endpoint} in your browser to access the llama.cpp chat interface.
Use the api_key above as the API Key if prompted.

[Service status]
llama-server = ${_llama_status}$(is_lb_mode && printf '\nlitellm-proxy = %s' "${_proxy_status}")
tls          = ${_tls_mode}

[OpenAI-compatible API]
Base URL  : ${_endpoint}/v1
API Key   : ${_password}
Model     : openai/${ACTIVE_MODEL_ID}

[OpenHands / other OpenAI clients]
Model     : openai/${ACTIVE_MODEL_ID}
Base URL  : ${_endpoint}/v1
API Key   : ${_password}

[Test with curl]
curl -k -H "Authorization: Bearer ${_password}" ${_endpoint}/v1/chat/completions \\
  -H 'Content-Type: application/json' \\
  -d '{"model":"${ACTIVE_MODEL_ID}","messages":[{"role":"user","content":"Hello"}]}'
EOF

    # Append LB section if in load balancer mode
    if is_lb_mode; then
        local _n_remotes
        _n_remotes=$(echo "${ONEAPP_COPILOT_LB_BACKENDS}" | tr ',' '\n' | grep -c '[^[:space:]]' || true)
        cat >> "${_report}" <<EOF

[Load Balancer]
mode            = litellm (least-busy routing)
local_backend   = http://127.0.0.1:${LLAMA_PORT_LOCAL}
remote_backends = ${_n_remotes}
config          = ${LITELLM_CONFIG}
litellm_ui      = ${_endpoint}/ui
ui_username     = admin
ui_password     = ${_password}
EOF
    fi

    chmod 600 "${_report}"
    log_copilot info "Report file written to ${_report}"
}

# --------------------------------------------------------------------------
# register_with_lb -- phone home to a remote LiteLLM LB on boot
# --------------------------------------------------------------------------
register_with_lb() {
    local _lb_url="${ONEAPP_COPILOT_REGISTER_URL:-}"
    local _lb_key="${ONEAPP_COPILOT_REGISTER_KEY:-}"

    # Skip if not configured
    [[ -z "${_lb_url}" ]] && return 0

    if [[ -z "${_lb_key}" ]]; then
        log_copilot warning "ONEAPP_COPILOT_REGISTER_URL set but ONEAPP_COPILOT_REGISTER_KEY is empty -- skipping LB registration"
        return 0
    fi

    # Resolve this VM's IP (first non-loopback)
    local _my_ip
    _my_ip=$(hostname -I | awk '{print $1}')
    if [[ -z "${_my_ip}" ]]; then
        log_copilot warning "Could not determine VM IP -- skipping LB registration"
        return 0
    fi

    # Read local API key
    local _api_key
    _api_key=$(cat "${LLAMA_DATA_DIR}/password" 2>/dev/null || echo '')
    if [[ -z "${_api_key}" ]]; then
        log_copilot warning "No local API key found -- skipping LB registration"
        return 0
    fi

    # Resolve model_id from catalog for model_name (allow override)
    local _model_id="${ONEAPP_COPILOT_REGISTER_MODEL_NAME:-}"
    if [[ -z "${_model_id}" ]]; then
        _load_model_info
        _model_id="${ACTIVE_MODEL_ID:-devstral-small-2}"
    fi

    # Strip trailing slash from LB URL
    _lb_url="${_lb_url%/}"

    # Build backend ID: prefer site name, fall back to IP
    local _backend_suffix="${ONEAPP_COPILOT_REGISTER_SITE_NAME:-${_my_ip}}"
    local _backend_id="${_model_id}-${_backend_suffix}"

    log_copilot info "Registering with remote LB at ${_lb_url} (model=${_model_id}, id=${_backend_id})"

    local _response
    _response=$(curl -sk -w '\n%{http_code}' -X POST "${_lb_url}/model/new" \
        -H "Authorization: Bearer ${_lb_key}" \
        -H "Content-Type: application/json" \
        -d "{
            \"model_name\": \"${_model_id}\",
            \"litellm_params\": {
                \"model\": \"openai/${_model_id}\",
                \"api_key\": \"${_api_key}\",
                \"api_base\": \"https://${_my_ip}:${LLAMA_PORT}/v1\"
            },
            \"model_info\": {
                \"id\": \"${_backend_id}\"
            }
        }" 2>/dev/null) || true

    local _http_code
    _http_code=$(echo "${_response}" | tail -1)
    local _body
    _body=$(echo "${_response}" | sed '$d')

    if [[ "${_http_code}" == "200" ]] || [[ "${_http_code}" == "201" ]]; then
        # Save the model identifier for deregistration
        echo "${_backend_id}" > "${LB_MODEL_ID_FILE}"
        chmod 600 "${LB_MODEL_ID_FILE}"

        # Write deregister script for shutdown
        _write_deregister_script "${_lb_url}" "${_lb_key}"

        log_copilot info "Successfully registered with LB (id=${_backend_id})"
    else
        log_copilot warning "LB registration failed (HTTP ${_http_code}): ${_body}"
    fi
}

# --------------------------------------------------------------------------
# _write_deregister_script -- creates the shutdown-time deregister script
# --------------------------------------------------------------------------
_write_deregister_script() {
    local _lb_url="$1"
    local _lb_key="$2"

    cat > "${LB_DEREGISTER_SCRIPT}" <<DEREGEOF
#!/usr/bin/env bash
# Auto-generated by EuroCopilot -- deregisters this VM from remote LB on shutdown
LB_MODEL_ID_FILE="${LB_MODEL_ID_FILE}"
if [[ ! -f "\${LB_MODEL_ID_FILE}" ]]; then
    exit 0
fi
_model_id=\$(cat "\${LB_MODEL_ID_FILE}")
curl -sk -X POST "${_lb_url}/model/delete" \\
    -H "Authorization: Bearer ${_lb_key}" \\
    -H "Content-Type: application/json" \\
    -d "{\"id\": \"\${_model_id}\"}" >/dev/null 2>&1 || true
rm -f "\${LB_MODEL_ID_FILE}"
DEREGEOF
    chmod 755 "${LB_DEREGISTER_SCRIPT}"

    # Create systemd unit if not present
    if [[ ! -f "${LB_DEREGISTER_UNIT}" ]]; then
        cat > "${LB_DEREGISTER_UNIT}" <<UNITEOF
[Unit]
Description=EuroCopilot LB Deregistration
DefaultDependencies=no
Before=shutdown.target reboot.target halt.target
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
ExecStop=${LB_DEREGISTER_SCRIPT}

[Install]
WantedBy=multi-user.target
UNITEOF
        systemctl daemon-reload
        systemctl enable eurocopilot-lb-deregister.service
        systemctl start eurocopilot-lb-deregister.service
    fi
}

# --------------------------------------------------------------------------
# _register_lb_backends -- register local + static backends via LiteLLM API
#   Models registered via API are stored in DB (store_model_in_db=true) so
#   they can be managed from the UI without reappearing from the config file.
# --------------------------------------------------------------------------
_register_lb_backends() {
    local _key
    _key=$(cat "${LLAMA_DATA_DIR}/password" 2>/dev/null || echo 'changeme')
    local _lb="https://127.0.0.1:${LITELLM_PORT}"

    # Helper: POST /model/new (idempotent -- LiteLLM upserts by model_info.id)
    _add_model() {
        local _mid="$1" _name="$2" _base="$3" _api_key="$4"
        local _http_code
        _http_code=$(curl -sk -o /dev/null -w '%{http_code}' -X POST "${_lb}/model/new" \
            -H "Authorization: Bearer ${_key}" \
            -H "Content-Type: application/json" \
            -d "{
                \"model_name\": \"${_name}\",
                \"litellm_params\": {
                    \"model\": \"openai/${_name}\",
                    \"api_base\": \"${_base}\",
                    \"api_key\": \"${_api_key}\"
                },
                \"model_info\": { \"id\": \"${_mid}\" }
            }" 2>/dev/null) || _http_code="000"
        if [[ "${_http_code}" == "200" ]] || [[ "${_http_code}" == "201" ]]; then
            log_copilot info "Registered backend ${_mid} -> ${_base}"
        else
            log_copilot warning "Failed to register backend ${_mid} (HTTP ${_http_code})"
        fi
    }

    # Register static remote backends from ONEAPP_COPILOT_LB_BACKENDS (key@host:port,...)
    # Local backend is already in the config file (not API-managed).
    local _backends="${ONEAPP_COPILOT_LB_BACKENDS}"
    local _entries _entry _bkey _url _host
    IFS=',' read -ra _entries <<< "${_backends}"
    for _entry in "${_entries[@]}"; do
        _entry=$(echo "${_entry}" | xargs)
        [ -z "${_entry}" ] && continue
        _bkey="${_key}"
        _url="${_entry}"
        if [[ "${_entry}" == *@* ]]; then
            _bkey="${_entry%%@*}"
            _url="${_entry#*@}"
        fi
        [[ "${_url}" != https://* ]] && [[ "${_url}" != http://* ]] && _url="https://${_url}"
        _host=$(echo "${_url}" | sed 's|https\?://||;s|:.*||')
        _add_model "${ACTIVE_MODEL_ID}-${_host}" "${ACTIVE_MODEL_ID}" \
            "${_url}/v1" "${_bkey}"
    done
}

# --------------------------------------------------------------------------
# _setup_lb_healthcheck -- periodic health checker for dynamically registered
#   backends. Runs on the LB VM via systemd timer. Queries LiteLLM for all
#   models, health-checks each remote backend, removes unreachable ones.
# --------------------------------------------------------------------------
_setup_lb_healthcheck() {
    local _lb_key
    _lb_key=$(cat "${LLAMA_DATA_DIR}/password" 2>/dev/null || echo 'changeme')

    cat > "${LB_HEALTHCHECK_SCRIPT}" <<'HCEOF'
#!/usr/bin/env bash
# Auto-generated by EuroCopilot -- removes dead backends from LiteLLM LB
set -o pipefail

LB_URL="https://127.0.0.1:LITELLM_PORT_PLACEHOLDER"
LB_KEY="LB_KEY_PLACEHOLDER"
HEALTH_TIMEOUT=10
MAX_FAILURES=3
STATE_DIR="/var/lib/eurocopilot/healthcheck"
LOG="/var/log/one-appliance/eurocopilot.log"

mkdir -p "${STATE_DIR}"

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [INFO] healthcheck: $*" >> "${LOG}"; }

# Get all models from LiteLLM
models_json=$(curl -sk --max-time 10 "${LB_URL}/model/info" \
    -H "Authorization: Bearer ${LB_KEY}" 2>/dev/null) || {
    log "Could not reach LiteLLM API -- skipping health check cycle"
    exit 0
}

# Extract model entries: id and api_base
# LiteLLM /model/info returns { "data": [ { "model_info": {"id":...}, "litellm_params": {"api_base":...} } ] }
echo "${models_json}" | python3 -c "
import json, sys
data = json.load(sys.stdin).get('data', [])
for m in data:
    mid = m.get('model_info', {}).get('id', '')
    base = m.get('litellm_params', {}).get('api_base', '')
    if mid and base:
        print(f'{mid}|{base}')
" 2>/dev/null | while IFS='|' read -r model_id api_base; do
    # Skip local backends (127.0.0.1 or localhost)
    if [[ "${api_base}" == *"127.0.0.1"* ]] || [[ "${api_base}" == *"localhost"* ]]; then
        continue
    fi

    # Health check: strip /v1 suffix, hit /health
    health_url="${api_base%/v1}/health"
    http_code=$(curl -sk --max-time "${HEALTH_TIMEOUT}" -o /dev/null -w '%{http_code}' "${health_url}" 2>/dev/null) || http_code="000"

    state_file="${STATE_DIR}/${model_id}.failures"

    if [[ "${http_code}" == "200" ]]; then
        # Healthy -- reset failure counter
        rm -f "${state_file}"
    else
        # Unhealthy -- increment failure counter
        failures=$(cat "${state_file}" 2>/dev/null || echo 0)
        failures=$((failures + 1))
        echo "${failures}" > "${state_file}"

        if [[ ${failures} -ge ${MAX_FAILURES} ]]; then
            log "Removing dead backend ${model_id} (${api_base}) after ${failures} consecutive failures"
            curl -sk --max-time 10 -X POST "${LB_URL}/model/delete" \
                -H "Authorization: Bearer ${LB_KEY}" \
                -H "Content-Type: application/json" \
                -d "{\"id\": \"${model_id}\"}" >/dev/null 2>&1 || true
            rm -f "${state_file}"
        else
            log "Backend ${model_id} unhealthy (HTTP ${http_code}), failure ${failures}/${MAX_FAILURES}"
        fi
    fi
done
HCEOF

    # Replace placeholders with actual values
    sed -i "s|LITELLM_PORT_PLACEHOLDER|${LITELLM_PORT}|g" "${LB_HEALTHCHECK_SCRIPT}"
    sed -i "s|LB_KEY_PLACEHOLDER|${_lb_key}|g" "${LB_HEALTHCHECK_SCRIPT}"
    chmod 755 "${LB_HEALTHCHECK_SCRIPT}"

    # Systemd service (oneshot, triggered by timer)
    cat > "${LB_HEALTHCHECK_UNIT}" <<UNITEOF
[Unit]
Description=EuroCopilot LB Backend Health Check
After=eurocopilot-proxy.service

[Service]
Type=oneshot
ExecStart=${LB_HEALTHCHECK_SCRIPT}
UNITEOF

    # Systemd timer (every 60s)
    cat > "${LB_HEALTHCHECK_TIMER}" <<TIMEREOF
[Unit]
Description=EuroCopilot LB Backend Health Check Timer

[Timer]
OnBootSec=120
OnUnitActiveSec=60
AccuracySec=5

[Install]
WantedBy=timers.target
TIMEREOF

    systemctl daemon-reload
    systemctl enable eurocopilot-lb-healthcheck.timer
    systemctl start eurocopilot-lb-healthcheck.timer
    log_copilot info "LB health check timer enabled (every 60s, 3 strikes to remove)"
}

# ==========================================================================
#  LIFECYCLE: service_install  (Packer build-time, runs once)
# ==========================================================================
service_install() {
    init_copilot_log
    log_copilot info "=== service_install started ==="
    log_copilot info "Installing EuroCopilot appliance components (llama-server)"

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
    mkdir -p /etc/eurocopilot
    cat > /usr/local/bin/eurocopilot-start.sh <<'WRAPPER_EOF'
#!/bin/bash
source /etc/eurocopilot/env
ARGS=(
    --host "${LLAMA_HOST}"
    --port "${LLAMA_PORT}"
    --model "${LLAMA_MODEL}"
    --ctx-size "${LLAMA_CTX_SIZE}"
    --threads "${LLAMA_THREADS}"
    --flash-attn on
    --jinja
    --mlock
    --metrics
    --prio 2
    --api-key "${LLAMA_API_KEY}"
)
[ -n "${LLAMA_SSL_KEY}" ] && ARGS+=(--ssl-key-file "${LLAMA_SSL_KEY}" --ssl-cert-file "${LLAMA_SSL_CERT}")
exec /usr/local/bin/llama-server "${ARGS[@]}"
WRAPPER_EOF
    chmod +x /usr/local/bin/eurocopilot-start.sh

    # 6. Create systemd unit file (delegates to wrapper script)
    cat > "${LLAMA_SYSTEMD_UNIT}" <<'UNIT_EOF'
[Unit]
Description=EuroCopilot AI Coding Assistant (llama-server)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/eurocopilot-start.sh
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
    /opt/litellm/bin/pip install prisma nodeenv --quiet

    # Install PostgreSQL (required for LiteLLM Web UI -- prisma schema mandates postgresql)
    apt-get install -y -qq postgresql postgresql-client >/dev/null

    # Pre-generate prisma client so first boot doesn't need to do it
    (
        export PATH="/opt/litellm/bin:${PATH}"
        cd /opt/litellm/lib/python3.*/site-packages/litellm/proxy
        prisma generate --schema=schema.prisma 2>/dev/null || true
    )

    /opt/litellm/bin/pip cache purge >/dev/null 2>&1 || true

    # Create systemd unit for LiteLLM proxy
    cat > "${LITELLM_SYSTEMD_UNIT}" <<'UNIT_EOF'
[Unit]
Description=EuroCopilot LiteLLM Load Balancer
After=network-online.target eurocopilot.service postgresql.service
Wants=network-online.target
Requires=postgresql.service

[Service]
Type=simple
EnvironmentFile=/etc/eurocopilot/env
Environment=UI_USERNAME=admin
ExecStart=/opt/litellm/bin/litellm \
  --config /etc/eurocopilot/litellm-config.yaml \
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
    cat > /etc/profile.d/eurocopilot-banner.sh <<'BANNER_EOF'
#!/bin/bash
[[ $- == *i* ]] || return
_vm_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
_password=$(cat /var/lib/eurocopilot/password 2>/dev/null || echo 'see report')
_llama=$(systemctl is-active eurocopilot 2>/dev/null || echo 'unknown')
_model=$(cat /var/lib/eurocopilot/model_id 2>/dev/null || echo 'unknown')
_proxy=$(systemctl is-active eurocopilot-proxy 2>/dev/null)
printf '\n'
printf '  EuroCopilot -- Sovereign AI Coding Assistant\n'
printf '  =============================================\n'
if [ "${_proxy}" = "active" ]; then
printf '  Mode     : load balancer (litellm)\n'
else
printf '  Mode     : standalone (llama.cpp)\n'
fi
printf '  Status   : %s\n' "${_llama}"
printf '\n'
printf '  [OpenAI-compatible API]\n'
printf '  Base URL : https://%s:8443/v1\n' "${_vm_ip}"
printf '  API Key  : %s\n' "${_password}"
printf '  Model    : openai/%s\n' "${_model}"
printf '\n'
if [ "${_proxy}" = "active" ]; then
printf '  [Web UI]\n'
printf '  URL      : https://%s:8443/ui\n' "${_vm_ip}"
printf '  Login    : admin / %s\n' "${_password}"
printf '\n'
fi
printf '  Report   : cat /etc/one-appliance/config\n'
printf '  Logs     : tail -f /var/log/one-appliance/eurocopilot.log\n'
printf '\n'
BANNER_EOF
    chmod 0644 /etc/profile.d/eurocopilot-banner.sh

    log_copilot info "EuroCopilot appliance install complete (llama-server)"
}

# ==========================================================================
#  LIFECYCLE: service_configure  (runs at each VM boot)
# ==========================================================================
service_configure() {
    init_copilot_log
    log_copilot info "=== service_configure started ==="
    log_copilot info "Configuring EuroCopilot"

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
        # Ensure PostgreSQL is running and litellm DB exists (for Web UI)
        systemctl start postgresql
        local _lb_password
        _lb_password=$(cat "${LLAMA_DATA_DIR}/password" 2>/dev/null || echo 'changeme')
        sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='litellm'" | grep -q 1 || \
            sudo -u postgres psql -c "CREATE USER litellm WITH PASSWORD '${_lb_password}'"
        sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='litellm'" | grep -q 1 || \
            sudo -u postgres psql -c "CREATE DATABASE litellm OWNER litellm"
        # Push prisma schema (idempotent -- creates tables if missing)
        (
            export PATH="/opt/litellm/bin:${PATH}"
            export DATABASE_URL="postgresql://litellm:${_lb_password}@localhost:5432/litellm"
            cd /opt/litellm/lib/python3.*/site-packages/litellm/proxy
            prisma db push --schema=schema.prisma --accept-data-loss 2>/dev/null || true
        )
        generate_litellm_config
    fi

    # 8. Reload systemd to pick up any env file changes
    systemctl daemon-reload

    log_copilot info "EuroCopilot configuration complete"
}

# ==========================================================================
#  LIFECYCLE: service_bootstrap  (runs after configure, starts services)
# ==========================================================================
service_bootstrap() {
    init_copilot_log
    log_copilot info "=== service_bootstrap started ==="
    log_copilot info "Bootstrapping EuroCopilot"

    # 0. Load model info persisted by service_configure
    _load_model_info

    # 0b. Clean up services from previous mode (handles standalone <-> LB switching)
    if is_lb_mode; then
        # LB mode: llama-server must not be on :8443 from a previous standalone boot
        systemctl stop eurocopilot.service 2>/dev/null || true
    else
        # Standalone mode: disable proxy if it was enabled in a previous LB boot
        systemctl stop eurocopilot-proxy.service 2>/dev/null || true
        systemctl disable eurocopilot-proxy.service 2>/dev/null || true
        # Restart llama-server so it picks up the new env (0.0.0.0:8443 + TLS)
        # Without this, a still-running LB-mode process on 127.0.0.1:8444 makes
        # the later `systemctl start` a no-op, leaving :8443 unserved.
        systemctl stop eurocopilot.service 2>/dev/null || true
    fi

    # 1. Attempt Let's Encrypt before starting llama-server (port 80 is free)
    attempt_letsencrypt

    # 2. Enable and start llama-server (skip in LB mode -- LB is a pure proxy)
    if is_lb_mode; then
        systemctl disable eurocopilot.service 2>/dev/null || true
        log_copilot info "LB mode: skipping local llama-server (pure proxy)"
    else
        systemctl enable eurocopilot.service
        systemctl start eurocopilot.service
        # 3. Wait for llama-server readiness
        wait_for_llama
    fi

    # 3b. Add cross-site routes via local VR for multi-site LB
    #     VR VM lives at .99 on each site subnet and handles Tailscale
    #     subnet routing.  The local /24 is more specific so local
    #     traffic is unaffected.  192.168.100.0/21 covers sites 100-107.
    if is_lb_mode; then
        local _gw _vr_ip
        _gw=$(ip route show default | awk '{print $3; exit}')
        _vr_ip="${_gw%.*}.99"
        if ip route get "$_vr_ip" &>/dev/null && \
           ping -c1 -W2 "$_vr_ip" &>/dev/null; then
            ip route replace 192.168.100.0/21 via "$_vr_ip" 2>/dev/null && \
                log_copilot info "Cross-site route added: 192.168.100.0/21 via ${_vr_ip} (VR)"
        else
            log_copilot warn "VR at ${_vr_ip} unreachable -- skipping cross-site routes"
        fi
    fi

    # 4. Start LiteLLM proxy if in LB mode
    if is_lb_mode; then
        systemctl enable eurocopilot-proxy.service
        systemctl start eurocopilot-proxy.service
        wait_for_litellm
        # 4a. Register backends via API (not config file, so UI deletions stick)
        _register_lb_backends
        # 4b. Start health check timer to cull dead remote backends
        _setup_lb_healthcheck
    else
        # Standalone mode: stop health check timer if leftover from LB mode
        systemctl stop eurocopilot-lb-healthcheck.timer 2>/dev/null || true
        systemctl disable eurocopilot-lb-healthcheck.timer 2>/dev/null || true
    fi

    # 5. Write report file with connection info, credentials, client config
    write_report_file

    # 6. Register with remote LB if configured (standalone VMs only)
    register_with_lb

    if is_lb_mode; then
        log_copilot info "EuroCopilot bootstrap complete -- LiteLLM proxy on 0.0.0.0:${LITELLM_PORT}, llama-server on 127.0.0.1:${LLAMA_PORT_LOCAL}"
    else
        log_copilot info "EuroCopilot bootstrap complete -- llama-server on 0.0.0.0:${LLAMA_PORT}"
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
EuroCopilot Appliance
=====================

Sovereign AI coding assistant powered by llama-server (llama.cpp) serving
Devstral Small 2 24B (Q4_K_M quantization) on CPU. OpenAI-compatible API
for aider and other OpenAI clients. Native TLS, Bearer token auth, Prometheus metrics.

Configuration variables (set via OpenNebula context):
  ONEAPP_COPILOT_AI_MODEL          AI model from catalog (default: Devstral Small 2 24B)
                                Available: Devstral Small 2 24B, Mistral Small 24B,
                                Mistral Nemo 12B, Mistral 7B Instruct
  ONEAPP_COPILOT_CONTEXT_SIZE   Model context window in tokens (default: 32768)
                                Valid range: 512-131072 tokens
  ONEAPP_COPILOT_API_PASSWORD        API key / Bearer token (auto-generated sk-... if empty)
  ONEAPP_COPILOT_TLS_DOMAIN         FQDN for Let's Encrypt certificate (optional)
                                If empty, self-signed certificate is used
  ONEAPP_COPILOT_CPU_THREADS        CPU threads for inference (default: 0 = auto-detect)
                                Set to number of physical cores for best performance
  ONEAPP_COPILOT_LB_ENABLED         Enable LiteLLM load balancer mode (default: NO)
                                When YES, activates LiteLLM proxy on :8443 with Web UI
  ONEAPP_COPILOT_LB_BACKENDS        Remote backends for load balancing
                                Format: key@host:port,key@host:port
                                Requires ONEAPP_COPILOT_LB_ENABLED=YES

Ports:
  8443  HTTPS API (TLS + Bearer token auth + Prometheus metrics)

Service management:
  systemctl status eurocopilot        Check inference server status
  systemctl restart eurocopilot       Restart the inference server
  journalctl -u eurocopilot -f        Follow inference server logs
  systemctl status eurocopilot-proxy  Check LiteLLM proxy (LB mode only)
  journalctl -u eurocopilot-proxy -f  Follow proxy logs (LB mode only)

Configuration files:
  /etc/eurocopilot/env                            Environment file (llama-server config)
  /etc/ssl/eurocopilot/cert.pem                   TLS certificate (symlink)
  /etc/ssl/eurocopilot/key.pem                    TLS private key (symlink)
  /opt/models/                                     Model GGUF file(s)
  /etc/eurocopilot/litellm-config.yaml             LiteLLM config (LB mode only)

Report and logs:
  /etc/one-appliance/config                    Service report (credentials, client config)
  /var/log/one-appliance/eurocopilot.log       Application log (all stages)

Health check:
  curl -k https://localhost:8443/health

Prometheus metrics:
  curl -k https://localhost:8443/metrics

Test inference:
  curl -k -H "Authorization: Bearer PASSWORD" https://localhost:8443/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -d '{"model":"devstral-small-2","messages":[{"role":"user","content":"Hello"}]}'

Password retrieval:
  cat /var/lib/eurocopilot/password
HELP
}

# ==========================================================================
#  HELPER: resolve_model  (determine model GGUF path, download if URL)
# ==========================================================================

# Globals set by resolve_model(), consumed by generate_llama_env/write_report
ACTIVE_MODEL_PATH=""
ACTIVE_MODEL_ID=""

resolve_model() {
    local _selection="${ONEAPP_COPILOT_AI_MODEL:-Devstral Small 2 (24B ~14GB built-in)}"

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
    if ! curl -4 -fSL --connect-timeout 15 --retry 2 --progress-bar -o "${ACTIVE_MODEL_PATH}" "${_hf_url}"; then
        log_copilot error "Failed to download model from ${_hf_url}"
        rm -f "${ACTIVE_MODEL_PATH}"

        # Graceful fallback: use built-in Devstral if available
        local _fallback="${LLAMA_MODEL_DIR}/${BUILTIN_MODEL_GGUF}"
        if [ -f "${_fallback}" ]; then
            local _fb_size
            _fb_size=$(stat -c%s "${_fallback}" 2>/dev/null || echo 0)
            if [ "${_fb_size}" -gt 1000000000 ]; then
                log_copilot warning "Falling back to built-in Devstral (download failed -- check VM internet connectivity)"
                ACTIVE_MODEL_ID="devstral-small-2"
                ACTIVE_MODEL_PATH="${_fallback}"
                _persist_model_info
                return 0
            fi
        fi
        log_copilot error "No fallback model available. Ensure the VM has internet access and retry."
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
        -subj "/CN=EuroCopilot" \
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
        _password="sk-$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 48)"
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

    local _threads="${ONEAPP_COPILOT_CPU_THREADS:-0}"
    if [ "${_threads}" = "0" ] || [ -z "${_threads}" ]; then
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

    mkdir -p /etc/eurocopilot

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
            log_copilot error "llama-server not ready after ${_timeout}s -- check: journalctl -u eurocopilot"
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

    # LB is a pure proxy -- no local llama-server.
    # All backends (including any local standalone VM) are registered via API/DB
    # so they can be managed from the UI.
    cat > "${LITELLM_CONFIG}" <<EOF
model_list: []
EOF

    # Append router and general settings
    cat >> "${LITELLM_CONFIG}" <<EOF

router_settings:
  routing_strategy: "least-busy"
  allowed_fails: 2
  cooldown_time: 30

litellm_settings:
  ssl_verify: false
  default_model: "${ACTIVE_MODEL_ID}"

general_settings:
  master_key: "${_local_password}"
  database_url: "postgresql://litellm:${_local_password}@localhost:5432/litellm"

environment_variables:
  STORE_MODEL_IN_DB: "True"
  UI_USERNAME: "admin"
  UI_PASSWORD: "${_local_password}"
EOF

    chmod 0600 "${LITELLM_CONFIG}"
    log_copilot info "LiteLLM config generated (pure proxy, backends via API)"
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
        cat > /etc/letsencrypt/renewal-hooks/deploy/eurocopilot-restart.sh <<'HOOK'
#!/bin/bash
systemctl restart eurocopilot
# Also restart LiteLLM proxy if active (LB mode uses TLS on the proxy)
systemctl is-active --quiet eurocopilot-proxy && systemctl restart eurocopilot-proxy
HOOK
        chmod +x /etc/letsencrypt/renewal-hooks/deploy/eurocopilot-restart.sh
    else
        log_copilot warning "Let's Encrypt failed for ${_domain} -- keeping self-signed certificate"
        log_copilot warning "Ensure: DNS resolves ${_domain} to this VM, port 80 is reachable from internet"
    fi
}
