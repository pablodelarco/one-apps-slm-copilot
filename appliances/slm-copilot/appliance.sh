#!/usr/bin/env bash
# --------------------------------------------------------------------------
# SLM-Copilot -- ONE-APPS Appliance Lifecycle Script
#
# Implements the one-apps service_* interface for a sovereign AI coding
# assistant powered by LocalAI + Devstral Small 2 24B, packaged as an
# OpenNebula marketplace appliance. CPU-only inference, no GPU required.
# --------------------------------------------------------------------------

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

# ==========================================================================
#  LIFECYCLE: service_install  (Packer build-time, runs once)
# ==========================================================================
service_install() {
    msg info "Installing SLM-Copilot appliance components"

    # 1. Install runtime dependencies
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq jq >/dev/null

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

    # 6. Set ownership
    chown -R "${LOCALAI_UID}:${LOCALAI_GID}" "${LOCALAI_BASE_DIR}"

    msg info "SLM-Copilot appliance install complete (LocalAI v${LOCALAI_VERSION})"
}

# ==========================================================================
#  LIFECYCLE: service_configure  (runs at each VM boot)
# ==========================================================================
service_configure() {
    msg info "Configuring SLM-Copilot"
    # Implemented in plan 01-03
}

# ==========================================================================
#  LIFECYCLE: service_bootstrap  (runs after configure, starts services)
# ==========================================================================
service_bootstrap() {
    msg info "Bootstrapping SLM-Copilot"
    # Implemented in plan 01-02
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

This appliance runs a sovereign AI coding assistant powered by LocalAI
serving Devstral Small 2 24B (Q4_K_M quantization) on CPU.

Key configuration variables (set via OpenNebula context):
  ONEAPP_COPILOT_CONTEXT_SIZE   Model context window in tokens (default: 32768)
  ONEAPP_COPILOT_THREADS        CPU threads for inference, 0=auto (default: 0)

Ports:
  8080  LocalAI API (localhost only, proxied by Nginx)

Service management:
  systemctl status  local-ai
  systemctl restart local-ai
  journalctl -u local-ai -f

Configuration files:
  /opt/local-ai/config/local-ai.env     Environment variables
  /opt/local-ai/models/                 Model YAML + GGUF weights
  /etc/systemd/system/local-ai.service  Systemd unit
HELP
}
