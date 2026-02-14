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
)

# --------------------------------------------------------------------------
# Default value assignments
# --------------------------------------------------------------------------
ONEAPP_COPILOT_CONTEXT_SIZE="${ONEAPP_COPILOT_CONTEXT_SIZE:-32768}"
ONEAPP_COPILOT_THREADS="${ONEAPP_COPILOT_THREADS:-0}"

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

# ==========================================================================
#  LIFECYCLE: service_install  (Packer build-time, runs once)
# ==========================================================================
service_install() {
    msg info "Installing SLM-Copilot appliance components"

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
    msg info "Downloading LocalAI v${LOCALAI_VERSION} binary"
    curl -fSL -o "${LOCALAI_BIN}" \
        "https://github.com/mudler/LocalAI/releases/download/v${LOCALAI_VERSION}/local-ai-Linux-x86_64"
    chmod +x "${LOCALAI_BIN}"

    # 5. Pre-install llama-cpp backend (INFER-09)
    msg info "Pre-installing llama-cpp backend"
    "${LOCALAI_BIN}" backends install llama-cpp

    # 6. Download GGUF model (INFER-03)
    msg info "Downloading Devstral Small 2 Q4_K_M model (~14.3 GB)"
    curl -fSL -C - -o "${LOCALAI_MODELS_DIR}/${LOCALAI_GGUF_FILE}" \
        "${LOCALAI_GGUF_URL}"

    # Verify download size
    local _file_size
    _file_size=$(stat -c%s "${LOCALAI_MODELS_DIR}/${LOCALAI_GGUF_FILE}")
    if [ "${_file_size}" -lt 14000000000 ]; then
        msg error "GGUF file is only ${_file_size} bytes -- expected ~14.3 GB. Download may be corrupted."
        exit 1
    fi
    msg info "GGUF model downloaded ($((_file_size / 1073741824)) GB)"

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

    msg info "Pre-warming: starting LocalAI for build-time verification"
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
            msg error "Pre-warm: LocalAI not ready after 300s"
            kill "${_prewarm_pid}" 2>/dev/null || true
            wait "${_prewarm_pid}" 2>/dev/null || true
            exit 1
        fi
    done
    msg info "Pre-warm: LocalAI ready (${_elapsed}s)"

    # Run smoke test to verify inference works (INFER-01, INFER-02, INFER-05)
    smoke_test "http://127.0.0.1:8080" || {
        kill "${_prewarm_pid}" 2>/dev/null || true
        wait "${_prewarm_pid}" 2>/dev/null || true
        exit 1
    }

    # Clean shutdown
    kill "${_prewarm_pid}"
    wait "${_prewarm_pid}" 2>/dev/null || true
    msg info "Pre-warm: LocalAI shut down"

    # Remove pre-warm model YAML (service_configure generates the real one)
    rm -f "${LOCALAI_MODELS_DIR}/${LOCALAI_MODEL_NAME}.yaml"

    # 8. Set ownership
    chown -R "${LOCALAI_UID}:${LOCALAI_GID}" "${LOCALAI_BASE_DIR}"

    msg info "SLM-Copilot appliance install complete (LocalAI v${LOCALAI_VERSION})"
}

# ==========================================================================
#  LIFECYCLE: service_configure  (runs at each VM boot)
# ==========================================================================
service_configure() {
    msg info "Configuring SLM-Copilot"

    # 1. Validate context variables (fail-fast on invalid values)
    validate_config

    # 2. Ensure directory structure exists (idempotent)
    mkdir -p "${LOCALAI_MODELS_DIR}" "${LOCALAI_CONFIG_DIR}"

    # 3. Check for AVX2 support (warn only, don't fail)
    if ! grep -q avx2 /proc/cpuinfo; then
        msg warning "CPU does not support AVX2 -- LocalAI inference may fail (SIGILL) or be very slow"
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

    msg info "SLM-Copilot configuration complete"
}

# ==========================================================================
#  LIFECYCLE: service_bootstrap  (runs after configure, starts services)
# ==========================================================================
service_bootstrap() {
    msg info "Bootstrapping SLM-Copilot"

    # 1. Enable and start LocalAI
    systemctl enable local-ai.service
    systemctl start local-ai.service

    # 2. Wait for readiness (INFER-05)
    wait_for_localai

    msg info "SLM-Copilot bootstrap complete -- LocalAI serving on 127.0.0.1:8080"
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

Configuration variables (set via OpenNebula context):
  ONEAPP_COPILOT_CONTEXT_SIZE   Model context window in tokens (default: 32768)
                                Valid range: 512-131072 tokens
  ONEAPP_COPILOT_THREADS        CPU threads for inference (default: 0 = auto-detect)
                                Set to number of physical cores for best performance

Ports:
  8080  LocalAI API (127.0.0.1 only -- not exposed to the network)

Service management:
  systemctl status local-ai          Check service status
  systemctl restart local-ai         Restart the inference server
  systemctl stop local-ai            Stop the inference server
  journalctl -u local-ai -f          Follow live logs

Configuration files:
  /opt/local-ai/models/devstral-small-2.yaml   Model configuration
  /opt/local-ai/config/local-ai.env            Environment variables
  /etc/systemd/system/local-ai.service         Systemd unit

Health check:
  curl http://127.0.0.1:8080/readyz

Test inference:
  curl http://127.0.0.1:8080/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -d '{"model":"devstral-small-2","messages":[{"role":"user","content":"Hello"}]}'
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
    msg info "Model YAML written to ${LOCALAI_MODELS_DIR}/${LOCALAI_MODEL_NAME}.yaml (context_size=${ONEAPP_COPILOT_CONTEXT_SIZE}, threads=${ONEAPP_COPILOT_THREADS})"
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
    msg info "Environment file written to ${LOCALAI_ENV_FILE}"
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
    msg info "Systemd unit written to ${LOCALAI_SYSTEMD_UNIT}"
}

# ==========================================================================
#  HELPER: wait_for_localai  (poll /readyz, 300s timeout)
# ==========================================================================
wait_for_localai() {
    local _timeout=300
    local _elapsed=0
    msg info "Waiting for LocalAI readiness (timeout: ${_timeout}s)"
    while ! curl -sf http://127.0.0.1:8080/readyz >/dev/null 2>&1; do
        sleep 5
        _elapsed=$((_elapsed + 5))
        if [ "${_elapsed}" -ge "${_timeout}" ]; then
            msg error "LocalAI not ready after ${_timeout}s -- check: journalctl -u local-ai"
            exit 1
        fi
    done
    msg info "LocalAI ready (${_elapsed}s)"
}

# ==========================================================================
#  HELPER: validate_config  (fail-fast on invalid context variable values)
# ==========================================================================
validate_config() {
    local _errors=0

    # ONEAPP_COPILOT_CONTEXT_SIZE: must be a positive integer, reasonable range 512-131072
    if ! [[ "${ONEAPP_COPILOT_CONTEXT_SIZE}" =~ ^[1-9][0-9]*$ ]]; then
        msg error "ONEAPP_COPILOT_CONTEXT_SIZE='${ONEAPP_COPILOT_CONTEXT_SIZE}' -- must be a positive integer"
        _errors=$((_errors + 1))
    elif [ "${ONEAPP_COPILOT_CONTEXT_SIZE}" -lt 512 ]; then
        msg error "ONEAPP_COPILOT_CONTEXT_SIZE='${ONEAPP_COPILOT_CONTEXT_SIZE}' -- minimum 512 tokens"
        _errors=$((_errors + 1))
    elif [ "${ONEAPP_COPILOT_CONTEXT_SIZE}" -gt 131072 ]; then
        msg warning "ONEAPP_COPILOT_CONTEXT_SIZE='${ONEAPP_COPILOT_CONTEXT_SIZE}' -- very large context, may cause OOM on 32 GB VM"
    fi

    # ONEAPP_COPILOT_THREADS: must be a non-negative integer (0 = auto-detect)
    if ! [[ "${ONEAPP_COPILOT_THREADS}" =~ ^[0-9]+$ ]]; then
        msg error "ONEAPP_COPILOT_THREADS='${ONEAPP_COPILOT_THREADS}' -- must be a non-negative integer (0=auto)"
        _errors=$((_errors + 1))
    fi

    # Abort on validation errors
    if [ "${_errors}" -gt 0 ]; then
        msg error "Configuration validation failed with ${_errors} error(s) -- aborting"
        exit 1
    fi

    msg info "Configuration validation passed (context_size=${ONEAPP_COPILOT_CONTEXT_SIZE}, threads=${ONEAPP_COPILOT_THREADS})"
}

# ==========================================================================
#  HELPER: smoke_test  (verify chat completions, streaming, and health)
# ==========================================================================
smoke_test() {
    local _endpoint="${1:-http://127.0.0.1:8080}"

    msg info "Running smoke test against ${_endpoint}"

    # Test 1: Non-streaming chat completion (INFER-01)
    local _response
    _response=$(curl -sf "${_endpoint}/v1/chat/completions" \
        -H 'Content-Type: application/json' \
        -d "{\"model\":\"${LOCALAI_MODEL_NAME}\",\"messages\":[{\"role\":\"user\",\"content\":\"Write a Python hello world\"}],\"max_tokens\":50}") || {
        msg error "Smoke test: chat completion request failed"
        return 1
    }
    echo "${_response}" | jq -e '.choices[0].message.content' >/dev/null 2>&1 || {
        msg error "Smoke test: no content in chat completion response"
        return 1
    }
    msg info "Smoke test: chat completion OK"

    # Test 2: Streaming chat completion (INFER-02)
    curl -sf "${_endpoint}/v1/chat/completions" \
        -H 'Content-Type: application/json' \
        -d "{\"model\":\"${LOCALAI_MODEL_NAME}\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hello\"}],\"max_tokens\":10,\"stream\":true}" \
        | grep -q 'data:' || {
        msg error "Smoke test: streaming response has no SSE data lines"
        return 1
    }
    msg info "Smoke test: streaming OK"

    # Test 3: Health endpoint (INFER-05)
    curl -sf "${_endpoint}/readyz" >/dev/null 2>&1 || {
        msg error "Smoke test: /readyz did not return 200"
        return 1
    }
    msg info "Smoke test: health check OK"

    msg info "All smoke tests passed"
    return 0
}
