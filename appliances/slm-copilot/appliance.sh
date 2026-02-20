#!/usr/bin/env bash
# --------------------------------------------------------------------------
# SLM-Copilot -- ONE-APPS Appliance Lifecycle Script
#
# Implements the one-apps service_* interface for a sovereign AI coding
# assistant powered by Ollama + Devstral Small 2 24B, packaged as an
# OpenNebula marketplace appliance. CPU-only inference, no GPU required.
# --------------------------------------------------------------------------

# shellcheck disable=SC2034  # ONE_SERVICE_* vars used by one-apps framework

ONE_SERVICE_NAME='Service SLM-Copilot - Sovereign AI Coding Assistant'
ONE_SERVICE_VERSION='1.1.0'
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='CPU-only AI coding copilot (Devstral Small 2 24B)'
ONE_SERVICE_DESCRIPTION='Sovereign AI coding assistant serving Devstral Small 2 24B
via Ollama. OpenAI-compatible API for Cline/VS Code integration.
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
readonly OLLAMA_MODEL_TAG="devstral"
readonly OLLAMA_MODEL_NAME="devstral-small-2"
readonly OLLAMA_PORT=11434
readonly OLLAMA_SYSTEMD_OVERRIDE="/etc/systemd/system/ollama.service.d/override.conf"
readonly OLLAMA_MODELFILE="/etc/ollama/Modelfile"
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
    local _ollama_status
    _ollama_status=$(systemctl is-active ollama 2>/dev/null || echo unknown)
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
backend      = ollama (llama.cpp)
quantization = Q4_K_M (24B parameters)
context_size = ${ONEAPP_COPILOT_CONTEXT_SIZE}
threads      = ${ONEAPP_COPILOT_THREADS}

[Service status]
ollama       = ${_ollama_status}
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

    # 2. Install Ollama
    log_copilot info "Installing Ollama"
    curl -fsSL https://ollama.com/install.sh | sh

    # 3. Start Ollama temporarily for model pull
    log_copilot info "Starting Ollama for model pull"
    systemctl start ollama
    wait_for_ollama

    # 4. Pull Devstral model from Ollama registry
    log_copilot info "Pulling ${OLLAMA_MODEL_TAG} model (this may take a while)"
    ollama pull "${OLLAMA_MODEL_TAG}"

    # 5. Create custom model with Modelfile
    mkdir -p "$(dirname "${OLLAMA_MODELFILE}")"
    cat > "${OLLAMA_MODELFILE}" <<MODELFILE
FROM ${OLLAMA_MODEL_TAG}
PARAMETER temperature 0.15
PARAMETER top_p 0.95
PARAMETER num_ctx 2048
PARAMETER num_thread 2
MODELFILE
    log_copilot info "Creating custom model ${OLLAMA_MODEL_NAME} from Modelfile"
    ollama create "${OLLAMA_MODEL_NAME}" -f "${OLLAMA_MODELFILE}"

    # 6. Build-time smoke test
    smoke_test "http://127.0.0.1:${OLLAMA_PORT}" || {
        systemctl stop ollama
        exit 1
    }

    # Clean shutdown
    systemctl stop ollama
    log_copilot info "Ollama stopped after build-time verification"

    # 7. Install SSH login banner
    cat > /etc/profile.d/slm-copilot-banner.sh <<'BANNER_EOF'
#!/bin/bash
[[ $- == *i* ]] || return
_vm_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
_password=$(cat /var/lib/slm-copilot/password 2>/dev/null || echo 'see report')
_ollama=$(systemctl is-active ollama 2>/dev/null || echo 'unknown')
_nginx=$(systemctl is-active nginx 2>/dev/null || echo 'unknown')
printf '\n'
printf '  SLM-Copilot -- Sovereign AI Coding Assistant\n'
printf '  =============================================\n'
printf '  Endpoint : https://%s\n' "${_vm_ip}"
printf '  Username : copilot\n'
printf '  Password : %s\n' "${_password}"
printf '  Model    : devstral-small-2 (24B Q4_K_M)\n'
printf '  Ollama   : %s\n' "${_ollama}"
printf '  Nginx    : %s\n' "${_nginx}"
printf '\n'
printf '  Report   : cat /etc/one-appliance/config\n'
printf '  Logs     : tail -f /var/log/one-appliance/slm-copilot.log\n'
printf '\n'
BANNER_EOF
    chmod 0644 /etc/profile.d/slm-copilot-banner.sh

    log_copilot info "SLM-Copilot appliance install complete (Ollama)"
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
        log_copilot warning "CPU does not support AVX2 -- Ollama inference may fail (SIGILL) or be very slow"
    fi

    # 3. Generate Modelfile (applied in bootstrap after Ollama starts)
    generate_modelfile

    # 4. Generate systemd drop-in override for Ollama
    generate_ollama_env

    # 5. Reload systemd
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

    # 1. Enable and start Ollama
    systemctl enable ollama.service
    systemctl start ollama.service

    # 2. Wait for readiness
    wait_for_ollama

    # 3. Apply Modelfile (requires running server)
    log_copilot info "Applying Modelfile to create ${OLLAMA_MODEL_NAME}"
    ollama create "${OLLAMA_MODEL_NAME}" -f "${OLLAMA_MODELFILE}"

    # Phase 2: Start Nginx reverse proxy
    systemctl enable nginx
    systemctl restart nginx

    # Phase 2: Attempt Let's Encrypt if domain is configured
    attempt_letsencrypt

    # Phase 3: Write report file with connection info, credentials, Cline config
    write_report_file

    log_copilot info "SLM-Copilot bootstrap complete -- Ollama on 127.0.0.1:${OLLAMA_PORT}, Nginx on 0.0.0.0:443"
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

Sovereign AI coding assistant powered by Ollama serving Devstral Small 2
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
  11434 Ollama API (127.0.0.1 only -- not exposed to the network)

Service management:
  systemctl status ollama            Check inference server status
  systemctl restart ollama           Restart the inference server
  systemctl status nginx             Check reverse proxy status
  systemctl restart nginx            Restart the reverse proxy
  journalctl -u ollama -f            Follow inference server logs
  journalctl -u nginx -f             Follow reverse proxy logs

Configuration files:
  /etc/ollama/Modelfile                                  Model configuration
  /etc/systemd/system/ollama.service.d/override.conf     Ollama environment overrides
  /etc/nginx/sites-available/slm-copilot.conf            Nginx reverse proxy config
  /etc/nginx/.htpasswd                                   Basic auth password file
  /etc/ssl/slm-copilot/cert.pem                          TLS certificate (symlink)
  /etc/ssl/slm-copilot/key.pem                           TLS private key (symlink)

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
#  HELPER: generate_modelfile  (write Ollama Modelfile)
# ==========================================================================
generate_modelfile() {
    mkdir -p "$(dirname "${OLLAMA_MODELFILE}")"
    cat > "${OLLAMA_MODELFILE}" <<MODELFILE
FROM ${OLLAMA_MODEL_TAG}
PARAMETER temperature 0.15
PARAMETER top_p 0.95
PARAMETER num_ctx ${ONEAPP_COPILOT_CONTEXT_SIZE}
PARAMETER num_thread ${ONEAPP_COPILOT_THREADS}
MODELFILE
    log_copilot info "Modelfile written to ${OLLAMA_MODELFILE} (num_ctx=${ONEAPP_COPILOT_CONTEXT_SIZE}, num_thread=${ONEAPP_COPILOT_THREADS})"
}

# ==========================================================================
#  HELPER: generate_ollama_env  (write systemd drop-in override)
# ==========================================================================
generate_ollama_env() {
    mkdir -p "$(dirname "${OLLAMA_SYSTEMD_OVERRIDE}")"
    cat > "${OLLAMA_SYSTEMD_OVERRIDE}" <<EOF
[Service]
Environment="OLLAMA_HOST=127.0.0.1:${OLLAMA_PORT}"
Environment="OLLAMA_KEEP_ALIVE=24h"
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_NUM_PARALLEL=1"
EOF
    log_copilot info "Ollama systemd override written to ${OLLAMA_SYSTEMD_OVERRIDE}"
}

# ==========================================================================
#  HELPER: wait_for_ollama  (poll root endpoint, 300s timeout)
# ==========================================================================
wait_for_ollama() {
    local _timeout=300
    local _elapsed=0
    log_copilot info "Waiting for Ollama readiness (timeout: ${_timeout}s)"
    while ! curl -sf "http://127.0.0.1:${OLLAMA_PORT}/" >/dev/null 2>&1; do
        sleep 5
        _elapsed=$((_elapsed + 5))
        if [ "${_elapsed}" -ge "${_timeout}" ]; then
            log_copilot error "Ollama not ready after ${_timeout}s -- check: journalctl -u ollama"
            exit 1
        fi
    done
    log_copilot info "Ollama ready (${_elapsed}s)"
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
    local _endpoint="${1:-http://127.0.0.1:${OLLAMA_PORT}}"

    log_copilot info "Running smoke test against ${_endpoint}"

    # Test 1: Non-streaming chat completion
    local _response
    _response=$(curl -sf "${_endpoint}/v1/chat/completions" \
        -H 'Content-Type: application/json' \
        -d "{\"model\":\"${OLLAMA_MODEL_NAME}\",\"messages\":[{\"role\":\"user\",\"content\":\"Write a Python hello world\"}],\"max_tokens\":50}") || {
        log_copilot error "Smoke test: chat completion request failed"
        return 1
    }
    echo "${_response}" | jq -e '.choices[0].message.content' >/dev/null 2>&1 || {
        log_copilot error "Smoke test: no content in chat completion response"
        return 1
    }
    log_copilot info "Smoke test: chat completion OK"

    # Test 2: Streaming chat completion
    curl -sf "${_endpoint}/v1/chat/completions" \
        -H 'Content-Type: application/json' \
        -d "{\"model\":\"${OLLAMA_MODEL_NAME}\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hello\"}],\"max_tokens\":10,\"stream\":true}" \
        | grep -q 'data:' || {
        log_copilot error "Smoke test: streaming response has no SSE data lines"
        return 1
    }
    log_copilot info "Smoke test: streaming OK"

    # Test 3: Health endpoint (Ollama root returns "Ollama is running")
    curl -sf "${_endpoint}/" >/dev/null 2>&1 || {
        log_copilot error "Smoke test: health check (/) did not return 200"
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
    chmod 0644 "${NGINX_HTPASSWD}"

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
        proxy_pass http://127.0.0.1:11434/;
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

        # Reverse proxy to Ollama
        proxy_pass http://127.0.0.1:11434;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # SSE streaming (ALL required)
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
