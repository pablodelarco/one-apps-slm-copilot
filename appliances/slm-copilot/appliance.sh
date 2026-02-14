#!/usr/bin/env bash
# --------------------------------------------------------------------------
# SLM-Copilot -- ONE-APPS Appliance Lifecycle Script
#
# Implements the one-apps service_* interface for a sovereign AI coding
# assistant powered by LocalAI + Devstral Small 2 24B, packaged as an
# OpenNebula marketplace appliance. CPU-only inference, no GPU required.
# --------------------------------------------------------------------------

# shellcheck disable=SC2034  # ONE_SERVICE_* vars used by one-apps framework

ONE_SERVICE_NAME='Service SLM-Copilot - Sovereign AI Coding Assistant'
ONE_SERVICE_VERSION='1.0.0'
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='CPU-only AI coding copilot (Devstral Small 2 24B)'
ONE_SERVICE_DESCRIPTION='Sovereign AI coding assistant serving Devstral Small 2 24B
via LocalAI. OpenAI-compatible API for Cline/VS Code integration.
CPU-only inference, no GPU required.'
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

    # Phase 2: Security & Access
    'ONEAPP_COPILOT_PASSWORD'      'configure' 'API password (auto-generated if empty)'      ''
    'ONEAPP_COPILOT_DOMAIN'        'configure' 'FQDN for Let'\''s Encrypt certificate'       ''
)

# --------------------------------------------------------------------------
# Default value assignments
# --------------------------------------------------------------------------
ONEAPP_COPILOT_CONTEXT_SIZE="${ONEAPP_COPILOT_CONTEXT_SIZE:-32768}"
ONEAPP_COPILOT_THREADS="${ONEAPP_COPILOT_THREADS:-0}"
ONEAPP_COPILOT_PASSWORD="${ONEAPP_COPILOT_PASSWORD:-}"
ONEAPP_COPILOT_DOMAIN="${ONEAPP_COPILOT_DOMAIN:-}"

# --------------------------------------------------------------------------
# Constants
# --------------------------------------------------------------------------
readonly LOCALAI_VERSION="3.11.0"
readonly LOCALAI_BASE_DIR="/opt/local-ai"
readonly LOCALAI_BIN="${LOCALAI_BASE_DIR}/bin/local-ai"
readonly LOCALAI_MODELS_DIR="${LOCALAI_BASE_DIR}/models"
readonly LOCALAI_CONFIG_DIR="${LOCALAI_BASE_DIR}/config"
readonly LOCALAI_ENV_FILE="${LOCALAI_CONFIG_DIR}/local-ai.env"
readonly LOCALAI_SYSTEMD_UNIT="/etc/systemd/system/local-ai.service"
readonly LOCALAI_MODEL_NAME="devstral-small-2"
readonly LOCALAI_GGUF_FILE="devstral-small-2-q4km.gguf"
readonly LOCALAI_GGUF_URL="https://huggingface.co/bartowski/mistralai_Devstral-Small-2-24B-Instruct-2512-GGUF/resolve/main/mistralai_Devstral-Small-2-24B-Instruct-2512-Q4_K_M.gguf"
readonly LOCALAI_UID=49999
readonly LOCALAI_GID=49999
readonly NGINX_CONF="/etc/nginx/sites-available/slm-copilot.conf"
readonly NGINX_CERT_DIR="/etc/ssl/slm-copilot"
readonly NGINX_HTPASSWD="/etc/nginx/.htpasswd"
readonly COPILOT_LOG="/var/log/one-appliance/slm-copilot.log"

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

    # ALWAYS read password from persisted file -- never from $ONEAPP_COPILOT_PASSWORD
    # which may be empty for auto-generated passwords (Pitfall 3)
    local _password
    _password=$(cat /var/lib/slm-copilot/password 2>/dev/null || echo 'unknown')

    # Determine TLS mode
    local _tls_mode="self-signed"
    if [ -n "${ONEAPP_COPILOT_DOMAIN:-}" ] && \
       [ -f "/etc/letsencrypt/live/${ONEAPP_COPILOT_DOMAIN}/fullchain.pem" ]; then
        _tls_mode="letsencrypt (${ONEAPP_COPILOT_DOMAIN})"
    fi

    # Determine endpoint URL (domain if set, IP otherwise)
    local _endpoint="https://${_vm_ip}"
    if [ -n "${ONEAPP_COPILOT_DOMAIN:-}" ]; then
        _endpoint="https://${ONEAPP_COPILOT_DOMAIN}"
    fi

    # Query live service status
    local _localai_status
    _localai_status=$(systemctl is-active local-ai 2>/dev/null || echo unknown)
    local _nginx_status
    _nginx_status=$(systemctl is-active nginx 2>/dev/null || echo unknown)

    # Write INI-style report to framework-defined path (defensive fallback)
    local _report="${ONE_SERVICE_REPORT:-/etc/one-appliance/config}"
    mkdir -p "$(dirname "${_report}")"

    cat > "${_report}" <<EOF
[Connection info]
endpoint     = ${_endpoint}
api_username = copilot
api_password = ${_password}

[Model]
name         = devstral-small-2
backend      = llama-cpp
quantization = Q4_K_M (24B parameters)
context_size = ${ONEAPP_COPILOT_CONTEXT_SIZE}
threads      = ${ONEAPP_COPILOT_THREADS}

[Service status]
local-ai     = ${_localai_status}
nginx        = ${_nginx_status}
tls          = ${_tls_mode}

[Cline VS Code setup]
1. Install Cline extension in VS Code
2. Click settings gear icon in Cline panel
3. Select "OpenAI Compatible" as API Provider
4. Enter these values:
   Base URL  : ${_endpoint}/v1
   API Key   : ${_password}
   Model ID  : devstral-small-2

[Cline JSON snippet]
{
  "apiProvider": "openai-compatible",
  "openAiBaseUrl": "${_endpoint}/v1",
  "openAiApiKey": "${_password}",
  "openAiModelId": "devstral-small-2"
}

[Test with curl]
curl -k -u copilot:${_password} ${_endpoint}/v1/chat/completions \\
  -H 'Content-Type: application/json' \\
  -d '{"model":"devstral-small-2","messages":[{"role":"user","content":"Hello"}]}'
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
    log_copilot info "Installing SLM-Copilot appliance components"

    # 1. Install runtime dependencies
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq jq >/dev/null

    # Phase 2: Install Nginx, htpasswd tool, and certbot
    apt-get install -y -qq nginx apache2-utils certbot >/dev/null

    # Remove default nginx site (conflicts with our config)
    rm -f /etc/nginx/sites-enabled/default

    # Create ACME challenge directory for certbot webroot
    mkdir -p /var/www/acme-challenge

    # 2. Create system user and group
    groupadd --system --gid "${LOCALAI_GID}" localai 2>/dev/null || true
    useradd --system --uid "${LOCALAI_UID}" --gid "${LOCALAI_GID}" \
        --home-dir "${LOCALAI_BASE_DIR}" --shell /usr/sbin/nologin localai 2>/dev/null || true

    # 3. Create directory structure
    mkdir -p "${LOCALAI_BASE_DIR}/bin" \
             "${LOCALAI_MODELS_DIR}" \
             "${LOCALAI_CONFIG_DIR}"

    # 4. Download LocalAI binary
    log_copilot info "Downloading LocalAI v${LOCALAI_VERSION} binary"
    curl -fSL -o "${LOCALAI_BIN}" \
        "https://github.com/mudler/LocalAI/releases/download/v${LOCALAI_VERSION}/local-ai-Linux-x86_64"
    chmod +x "${LOCALAI_BIN}"

    # 5. Pre-install llama-cpp backend (INFER-09)
    log_copilot info "Pre-installing llama-cpp backend"
    "${LOCALAI_BIN}" backends install llama-cpp

    # 6. Download GGUF model (INFER-03)
    log_copilot info "Downloading Devstral Small 2 Q4_K_M model (~14.3 GB)"
    curl -fSL -C - -o "${LOCALAI_MODELS_DIR}/${LOCALAI_GGUF_FILE}" \
        "${LOCALAI_GGUF_URL}"

    # Verify download size
    local _file_size
    _file_size=$(stat -c%s "${LOCALAI_MODELS_DIR}/${LOCALAI_GGUF_FILE}")
    if [ "${_file_size}" -lt 14000000000 ]; then
        log_copilot error "GGUF file is only ${_file_size} bytes -- expected ~14.3 GB. Download may be corrupted."
        exit 1
    fi
    log_copilot info "GGUF model downloaded ($((_file_size / 1073741824)) GB)"

    # 7. Build-time pre-warming (INFER-09 verification)
    # Generate a minimal model YAML for pre-warming
    cat > "${LOCALAI_MODELS_DIR}/${LOCALAI_MODEL_NAME}.yaml" <<YAML
name: ${LOCALAI_MODEL_NAME}
backend: llama-cpp
parameters:
  model: ${LOCALAI_GGUF_FILE}
context_size: 2048
threads: 2
mmap: true
mmlock: false
use_jinja: true
YAML

    log_copilot info "Pre-warming: starting LocalAI for build-time verification"
    "${LOCALAI_BIN}" run \
        --address 127.0.0.1:8080 \
        --models-path "${LOCALAI_MODELS_DIR}" \
        --disable-webui &
    local _prewarm_pid=$!

    # Wait for readiness (model loading can take 60-180s on CPU)
    local _elapsed=0
    while ! curl -sf http://127.0.0.1:8080/readyz >/dev/null 2>&1; do
        sleep 5
        _elapsed=$((_elapsed + 5))
        if [ "${_elapsed}" -ge 300 ]; then
            log_copilot error "Pre-warm: LocalAI not ready after 300s"
            kill "${_prewarm_pid}" 2>/dev/null || true
            wait "${_prewarm_pid}" 2>/dev/null || true
            exit 1
        fi
    done
    log_copilot info "Pre-warm: LocalAI ready (${_elapsed}s)"

    # Run smoke test to verify inference works (INFER-01, INFER-02, INFER-05)
    smoke_test "http://127.0.0.1:8080" || {
        kill "${_prewarm_pid}" 2>/dev/null || true
        wait "${_prewarm_pid}" 2>/dev/null || true
        exit 1
    }

    # Clean shutdown
    kill "${_prewarm_pid}"
    wait "${_prewarm_pid}" 2>/dev/null || true
    log_copilot info "Pre-warm: LocalAI shut down"

    # Remove pre-warm model YAML (service_configure generates the real one)
    rm -f "${LOCALAI_MODELS_DIR}/${LOCALAI_MODEL_NAME}.yaml"

    # 8. Install SSH login banner (ONE-08)
    cat > /etc/profile.d/slm-copilot-banner.sh <<'BANNER_EOF'
#!/bin/bash
[[ $- == *i* ]] || return
_vm_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
_password=$(cat /var/lib/slm-copilot/password 2>/dev/null || echo 'see report')
_localai=$(systemctl is-active local-ai 2>/dev/null || echo 'unknown')
_nginx=$(systemctl is-active nginx 2>/dev/null || echo 'unknown')
printf '\n'
printf '  SLM-Copilot -- Sovereign AI Coding Assistant\n'
printf '  =============================================\n'
printf '  Endpoint : https://%s\n' "${_vm_ip}"
printf '  Username : copilot\n'
printf '  Password : %s\n' "${_password}"
printf '  Model    : devstral-small-2 (24B Q4_K_M)\n'
printf '  LocalAI  : %s\n' "${_localai}"
printf '  Nginx    : %s\n' "${_nginx}"
printf '\n'
printf '  Report   : cat /etc/one-appliance/config\n'
printf '  Logs     : tail -f /var/log/one-appliance/slm-copilot.log\n'
printf '\n'
BANNER_EOF
    chmod 0644 /etc/profile.d/slm-copilot-banner.sh

    # 9. Set ownership
    chown -R "${LOCALAI_UID}:${LOCALAI_GID}" "${LOCALAI_BASE_DIR}"

    log_copilot info "SLM-Copilot appliance install complete (LocalAI v${LOCALAI_VERSION})"
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

    # 2. Ensure directory structure exists (idempotent)
    mkdir -p "${LOCALAI_MODELS_DIR}" "${LOCALAI_CONFIG_DIR}"

    # 3. Check for AVX2 support (warn only, don't fail)
    if ! grep -q avx2 /proc/cpuinfo; then
        log_copilot warning "CPU does not support AVX2 -- LocalAI inference may fail (SIGILL) or be very slow"
    fi

    # 4. Generate model YAML (INFER-01, INFER-06, INFER-07)
    #    CRITICAL: use_jinja must be true for Devstral chat template
    generate_model_yaml

    # 5. Generate environment file
    generate_env_file

    # 6. Generate systemd unit file (INFER-04, INFER-08)
    generate_systemd_unit

    # 7. Reload systemd
    systemctl daemon-reload

    # Phase 2: Nginx reverse proxy with TLS and auth
    # Order matters: certs and htpasswd MUST exist before nginx config is written
    generate_selfsigned_cert
    generate_htpasswd
    generate_nginx_config

    log_copilot info "SLM-Copilot configuration complete"
}

# ==========================================================================
#  LIFECYCLE: service_bootstrap  (runs after configure, starts services)
# ==========================================================================
service_bootstrap() {
    init_copilot_log
    log_copilot info "=== service_bootstrap started ==="
    log_copilot info "Bootstrapping SLM-Copilot"

    # 1. Enable and start LocalAI
    systemctl enable local-ai.service
    systemctl start local-ai.service

    # 2. Wait for readiness (INFER-05)
    wait_for_localai

    # Phase 2: Start Nginx reverse proxy
    systemctl enable nginx
    systemctl restart nginx

    # Phase 2: Attempt Let's Encrypt if domain is configured (SEC-06, SEC-07)
    attempt_letsencrypt

    # Phase 3: Write report file with connection info, credentials, Cline config (ONE-02, ONE-05)
    write_report_file

    log_copilot info "SLM-Copilot bootstrap complete -- LocalAI on 127.0.0.1:8080, Nginx on 0.0.0.0:443"
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

Sovereign AI coding assistant powered by LocalAI serving Devstral Small 2
24B (Q4_K_M quantization) on CPU. OpenAI-compatible API for Cline/VS Code.
Nginx reverse proxy with TLS, basic auth, CORS, and SSE streaming.

Configuration variables (set via OpenNebula context):
  ONEAPP_COPILOT_CONTEXT_SIZE   Model context window in tokens (default: 32768)
                                Valid range: 512-131072 tokens
  ONEAPP_COPILOT_THREADS        CPU threads for inference (default: 0 = auto-detect)
                                Set to number of physical cores for best performance
  ONEAPP_COPILOT_PASSWORD       API password (auto-generated 16-char if empty)
                                Username is always 'copilot'
  ONEAPP_COPILOT_DOMAIN         FQDN for Let's Encrypt certificate (optional)
                                If empty, self-signed certificate is used

Ports:
  80    HTTP redirect to HTTPS (+ ACME challenge for Let's Encrypt)
  443   HTTPS API (TLS + basic auth)
  8080  LocalAI API (127.0.0.1 only -- not exposed to the network)

Service management:
  systemctl status local-ai          Check inference server status
  systemctl restart local-ai         Restart the inference server
  systemctl status nginx             Check reverse proxy status
  systemctl restart nginx            Restart the reverse proxy
  journalctl -u local-ai -f          Follow inference server logs
  journalctl -u nginx -f             Follow reverse proxy logs

Configuration files:
  /opt/local-ai/models/devstral-small-2.yaml   Model configuration
  /opt/local-ai/config/local-ai.env            Environment variables
  /etc/systemd/system/local-ai.service         Systemd unit
  /etc/nginx/sites-available/slm-copilot.conf  Nginx reverse proxy config
  /etc/nginx/.htpasswd                         Basic auth password file
  /etc/ssl/slm-copilot/cert.pem               TLS certificate (symlink)
  /etc/ssl/slm-copilot/key.pem                TLS private key (symlink)

Report and logs:
  /etc/one-appliance/config                    Service report (credentials, Cline config)
  /var/log/one-appliance/slm-copilot.log       Application log (all stages)

Health check:
  curl -k https://localhost/readyz
  curl -k https://localhost/health

Test inference:
  curl -k -u copilot:PASSWORD https://localhost/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -d '{"model":"devstral-small-2","messages":[{"role":"user","content":"Hello"}]}'

Password retrieval:
  cat /var/lib/slm-copilot/password
HELP
}

# ==========================================================================
#  HELPER: generate_model_yaml  (write model configuration)
# ==========================================================================
generate_model_yaml() {
    cat > "${LOCALAI_MODELS_DIR}/${LOCALAI_MODEL_NAME}.yaml" <<YAML
# Devstral Small 2 24B (Q4_K_M) -- generated at $(date -u +"%Y-%m-%dT%H:%M:%SZ")
name: ${LOCALAI_MODEL_NAME}
backend: llama-cpp
parameters:
  model: ${LOCALAI_GGUF_FILE}
  temperature: 0.15
  top_p: 0.95
context_size: ${ONEAPP_COPILOT_CONTEXT_SIZE}
threads: ${ONEAPP_COPILOT_THREADS}
mmap: true
mmlock: false
use_jinja: true
YAML
    chown "${LOCALAI_UID}:${LOCALAI_GID}" "${LOCALAI_MODELS_DIR}/${LOCALAI_MODEL_NAME}.yaml"
    log_copilot info "Model YAML written to ${LOCALAI_MODELS_DIR}/${LOCALAI_MODEL_NAME}.yaml (context_size=${ONEAPP_COPILOT_CONTEXT_SIZE}, threads=${ONEAPP_COPILOT_THREADS})"
}

# ==========================================================================
#  HELPER: generate_env_file  (write environment configuration)
# ==========================================================================
generate_env_file() {
    cat > "${LOCALAI_ENV_FILE}" <<EOF
# LocalAI environment -- generated at $(date -u +"%Y-%m-%dT%H:%M:%SZ")
LOCALAI_THREADS=${ONEAPP_COPILOT_THREADS}
LOCALAI_CONTEXT_SIZE=${ONEAPP_COPILOT_CONTEXT_SIZE}
LOCALAI_LOG_LEVEL=info
EOF
    chmod 0640 "${LOCALAI_ENV_FILE}"
    log_copilot info "Environment file written to ${LOCALAI_ENV_FILE}"
}

# ==========================================================================
#  HELPER: generate_systemd_unit  (write systemd service file)
# ==========================================================================
generate_systemd_unit() {
    cat > "${LOCALAI_SYSTEMD_UNIT}" <<EOF
[Unit]
Description=LocalAI LLM Inference Server (SLM-Copilot)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=localai
Group=localai
EnvironmentFile=${LOCALAI_ENV_FILE}
ExecStart=${LOCALAI_BIN} run \\
    --address 127.0.0.1:8080 \\
    --models-path ${LOCALAI_MODELS_DIR} \\
    --disable-webui
Restart=on-failure
RestartSec=10
TimeoutStartSec=300
LimitNOFILE=65536
OOMScoreAdjust=-500

[Install]
WantedBy=multi-user.target
EOF
    log_copilot info "Systemd unit written to ${LOCALAI_SYSTEMD_UNIT}"
}

# ==========================================================================
#  HELPER: wait_for_localai  (poll /readyz, 300s timeout)
# ==========================================================================
wait_for_localai() {
    local _timeout=300
    local _elapsed=0
    log_copilot info "Waiting for LocalAI readiness (timeout: ${_timeout}s)"
    while ! curl -sf http://127.0.0.1:8080/readyz >/dev/null 2>&1; do
        sleep 5
        _elapsed=$((_elapsed + 5))
        if [ "${_elapsed}" -ge "${_timeout}" ]; then
            log_copilot error "LocalAI not ready after ${_timeout}s -- check: journalctl -u local-ai"
            exit 1
        fi
    done
    log_copilot info "LocalAI ready (${_elapsed}s)"
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
#  HELPER: smoke_test  (verify chat completions, streaming, and health)
# ==========================================================================
smoke_test() {
    local _endpoint="${1:-http://127.0.0.1:8080}"

    log_copilot info "Running smoke test against ${_endpoint}"

    # Test 1: Non-streaming chat completion (INFER-01)
    local _response
    _response=$(curl -sf "${_endpoint}/v1/chat/completions" \
        -H 'Content-Type: application/json' \
        -d "{\"model\":\"${LOCALAI_MODEL_NAME}\",\"messages\":[{\"role\":\"user\",\"content\":\"Write a Python hello world\"}],\"max_tokens\":50}") || {
        log_copilot error "Smoke test: chat completion request failed"
        return 1
    }
    echo "${_response}" | jq -e '.choices[0].message.content' >/dev/null 2>&1 || {
        log_copilot error "Smoke test: no content in chat completion response"
        return 1
    }
    log_copilot info "Smoke test: chat completion OK"

    # Test 2: Streaming chat completion (INFER-02)
    curl -sf "${_endpoint}/v1/chat/completions" \
        -H 'Content-Type: application/json' \
        -d "{\"model\":\"${LOCALAI_MODEL_NAME}\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hello\"}],\"max_tokens\":10,\"stream\":true}" \
        | grep -q 'data:' || {
        log_copilot error "Smoke test: streaming response has no SSE data lines"
        return 1
    }
    log_copilot info "Smoke test: streaming OK"

    # Test 3: Health endpoint (INFER-05)
    curl -sf "${_endpoint}/readyz" >/dev/null 2>&1 || {
        log_copilot error "Smoke test: /readyz did not return 200"
        return 1
    }
    log_copilot info "Smoke test: health check OK"

    log_copilot info "All smoke tests passed"
    return 0
}

# ==========================================================================
#  HELPER: generate_selfsigned_cert  (self-signed X.509 with VM IP SAN)
# ==========================================================================
generate_selfsigned_cert() {
    local _vm_ip
    _vm_ip=$(hostname -I | awk '{print $1}')

    mkdir -p "${NGINX_CERT_DIR}"

    openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout "${NGINX_CERT_DIR}/selfsigned-key.pem" \
        -out "${NGINX_CERT_DIR}/selfsigned-cert.pem" \
        -days 3650 \
        -subj "/CN=SLM-Copilot" \
        -addext "subjectAltName=DNS:localhost,IP:127.0.0.1,IP:${_vm_ip}"

    chmod 0600 "${NGINX_CERT_DIR}/selfsigned-key.pem"
    chmod 0644 "${NGINX_CERT_DIR}/selfsigned-cert.pem"

    # Active cert symlinks (Let's Encrypt replaces these in plan 02-02)
    ln -sf "${NGINX_CERT_DIR}/selfsigned-cert.pem" "${NGINX_CERT_DIR}/cert.pem"
    ln -sf "${NGINX_CERT_DIR}/selfsigned-key.pem" "${NGINX_CERT_DIR}/key.pem"

    log_copilot info "Self-signed certificate generated for ${_vm_ip}"
}

# ==========================================================================
#  HELPER: generate_htpasswd  (basic auth password file)
# ==========================================================================
generate_htpasswd() {
    local _password="${ONEAPP_COPILOT_PASSWORD:-}"

    if [ -z "${_password}" ]; then
        _password=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)
        log_copilot info "Auto-generated API password (no ONEAPP_COPILOT_PASSWORD set)"
    fi

    htpasswd -cbB "${NGINX_HTPASSWD}" copilot "${_password}"
    chmod 0640 "${NGINX_HTPASSWD}"

    # Persist password for report file (Phase 3)
    mkdir -p /var/lib/slm-copilot
    echo "${_password}" > /var/lib/slm-copilot/password
    chmod 0600 /var/lib/slm-copilot/password

    log_copilot info "htpasswd written to ${NGINX_HTPASSWD} (user: copilot)"
}

# ==========================================================================
#  HELPER: generate_nginx_config  (TLS + auth + CORS + SSE + health)
# ==========================================================================
generate_nginx_config() {
    cat > "${NGINX_CONF}" <<'NGINX_EOF'
# /etc/nginx/sites-available/slm-copilot.conf
# Generated by SLM-Copilot appliance

# --- HTTP server (port 80): redirect to HTTPS + ACME challenge ---
server {
    listen 80 default_server;
    server_name _;

    # Let's Encrypt HTTP-01 challenge
    location ^~ /.well-known/acme-challenge/ {
        root /var/www/acme-challenge;
    }

    # Redirect everything else to HTTPS
    location / {
        return 301 https://$host$request_uri;
    }
}

# --- HTTPS server (port 443): TLS + auth + proxy ---
server {
    listen 443 ssl default_server;
    server_name _;

    # TLS configuration
    ssl_certificate     /etc/ssl/slm-copilot/cert.pem;
    ssl_certificate_key /etc/ssl/slm-copilot/key.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_buffer_size     4k;

    # CORS headers on ALL responses (including errors)
    add_header Access-Control-Allow-Origin "*" always;
    add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Authorization, Content-Type" always;

    # --- Health check endpoints (no auth) ---
    location = /readyz {
        auth_basic off;
        proxy_pass http://127.0.0.1:8080/readyz;
    }

    location = /health {
        auth_basic off;
        return 200 'ok\n';
        add_header Content-Type text/plain always;
    }

    # --- Main API proxy ---
    location / {
        # Handle OPTIONS preflight (no auth, no proxy)
        if ($request_method = OPTIONS) {
            add_header Access-Control-Allow-Origin "*" always;
            add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
            add_header Access-Control-Allow-Headers "Authorization, Content-Type" always;
            add_header Access-Control-Max-Age 86400 always;
            add_header Content-Length 0 always;
            return 204;
        }

        # Basic authentication
        auth_basic "SLM-Copilot API";
        auth_basic_user_file /etc/nginx/.htpasswd;

        # Reverse proxy to LocalAI
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # SSE streaming (ALL required -- see 02-RESEARCH.md Pattern 4)
        proxy_buffering off;
        proxy_cache off;
        proxy_set_header Connection '';
        proxy_set_header X-Accel-Buffering no;
        chunked_transfer_encoding off;
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;

        # Disable gzip for SSE (prevents buffering)
        gzip off;
    }
}
NGINX_EOF

    # Create symlink in sites-enabled
    ln -sf "${NGINX_CONF}" /etc/nginx/sites-enabled/slm-copilot.conf

    # Validate config before proceeding
    if ! nginx -t 2>&1; then
        log_copilot error "Nginx configuration validation failed -- check ${NGINX_CONF}"
        exit 1
    fi

    log_copilot info "Nginx config written to ${NGINX_CONF}"
}

# ==========================================================================
#  HELPER: attempt_letsencrypt  (certbot --webroot with graceful fallback)
# ==========================================================================
attempt_letsencrypt() {
    local _domain="${ONEAPP_COPILOT_DOMAIN:-}"

    if [ -z "${_domain}" ]; then
        log_copilot info "ONEAPP_COPILOT_DOMAIN not set -- using self-signed certificate"
        return 0
    fi

    log_copilot info "Attempting Let's Encrypt certificate for ${_domain}"

    # Ensure webroot directory structure exists
    mkdir -p /var/www/acme-challenge/.well-known/acme-challenge

    if certbot certonly \
        --non-interactive \
        --agree-tos \
        --register-unsafely-without-email \
        --webroot \
        -w /var/www/acme-challenge \
        -d "${_domain}" 2>&1; then

        # Success: switch active symlinks to Let's Encrypt certs
        ln -sf "/etc/letsencrypt/live/${_domain}/fullchain.pem" "${NGINX_CERT_DIR}/cert.pem"
        ln -sf "/etc/letsencrypt/live/${_domain}/privkey.pem" "${NGINX_CERT_DIR}/key.pem"
        nginx -s reload
        log_copilot info "Let's Encrypt certificate installed for ${_domain}"

        # Set up renewal deploy hook (nginx reload on cert renewal)
        mkdir -p /etc/letsencrypt/renewal-hooks/deploy
        cat > /etc/letsencrypt/renewal-hooks/deploy/nginx-reload.sh <<'HOOK'
#!/bin/bash
nginx -s reload
HOOK
        chmod +x /etc/letsencrypt/renewal-hooks/deploy/nginx-reload.sh
    else
        log_copilot warning "Let's Encrypt failed for ${_domain} -- keeping self-signed certificate"
        log_copilot warning "Ensure: DNS resolves ${_domain} to this VM, port 80 is reachable from internet"
    fi
}
