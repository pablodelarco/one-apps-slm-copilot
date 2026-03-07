# Changelog

All notable changes to the SLM-Copilot appliance will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [2.3.0] - 2026-03-07

### Changed

- Auto-generated API keys now use `sk-` prefix (OpenAI convention) with 48 random
  characters (51 chars total), replacing the previous 16-char bare hex tokens.

### Fixed

- SSH welcome banner now shows the local IP address instead of the public IP.
- Removed aider reference from banner; API key shown in Web UI login instructions.
- System users (slm-copilot, litellm, postgres) are created during packer build
  to prevent UID/GID conflicts at runtime.

### Added

- Persistent cross-site routes via VR for LB mode: backend VMs automatically add
  static routes to reach other site subnets through the local Virtual Router.

## [2.2.0] - 2026-03-04

### Added

- Zero-touch auto-registration: standalone VMs can automatically register as
  backends in a remote LiteLLM load balancer on boot and deregister on shutdown.
  Configure via ONEAPP_COPILOT_LB_URL and ONEAPP_COPILOT_LB_MASTER_KEY.
- Systemd deregistration service ensures clean removal from LB on VM shutdown/reboot.

## [2.1.1] - 2026-03-04

### Changed

- Replaced model catalog: removed base/completion-only models (Codestral 22B v0.1,
  Codestral Mamba 7B) that lack chat templates. New instruct-only catalog:
  Devstral Small 2 (24B, built-in), Mistral Small Instruct (24B),
  Mistral Nemo Instruct (12B), Mistral 7B Instruct (7B).
  Each entry now shows parameter count and approximate GGUF size.

### Fixed

- Removed commas from model list display names to prevent OpenNebula
  user_inputs list parser from splitting them into separate entries.

### Fixed

- Added `stop: ["<|im_end|>"]` to LiteLLM backend configs to prevent ChatML stop
  tokens from leaking into responses when routing through the load balancer.
- Added `STORE_MODEL_IN_DB: "True"` to LiteLLM environment to enable adding and
  removing models from the Web UI.

### Notes

- When connecting from clients that validate TLS certificates (e.g. OpenHands with
  httpx/litellm), the self-signed certificate will be rejected. Use a valid TLS
  certificate: configure Let's Encrypt via ONEAPP_COPILOT_TLS_DOMAIN, or expose the
  endpoint through a TLS-terminating proxy with a trusted certificate (e.g. Tailscale
  Funnel, Cloudflare Tunnel, or a reverse proxy with a CA-signed cert).

## [2.1.0] - 2026-02-25

### Added

- Optional LiteLLM load balancing across multiple SLM-Copilot VMs via ONEAPP_COPILOT_LB_BACKENDS
- Least-busy routing, automatic failover (2 fails = 30s cooldown), and cross-site distribution
- LiteLLM proxy systemd unit (slm-copilot-proxy.service) with TLS and master_key auth
- LiteLLM Web UI (${endpoint}/ui) for monitoring traffic, managing backends, creating API keys, and setting budgets
- PostgreSQL database for LiteLLM Web UI persistence (auto-provisioned in LB mode)
- Mode-switch cleanup: switching between standalone and LB mode across reboots is safe
- Let's Encrypt renewal hook restarts LiteLLM proxy when active

## [2.0.0] - 2026-02-23

### Changed

- Replaced Ollama + Nginx with bare llama-server (llama.cpp) as inference backend
- 30-50% better throughput with direct llama-server, smaller footprint (~90MB binary vs ~200MB+ Ollama)
- Native TLS, API key auth, CORS, and Prometheus metrics in llama-server (no reverse proxy needed)
- Bearer token authentication replaces basic auth (no username, API key only)
- Port changed from 443 to 8443 (llama-server direct HTTPS)
- Compiled with GGML_CPU_ALL_VARIANTS for automatic SIMD detection (SSE3/AVX/AVX2/AVX-512)
- CPU tuning: mlock, flash-attn, thread pinning, process priority
- Model GGUF baked directly into image from Hugging Face (no Ollama registry dependency)
- certbot standalone mode for Let's Encrypt (port 80 is free without nginx)
- Systemd unit name changed from ollama/nginx to slm-copilot

### Added

- ONEAPP_COPILOT_AI_MODEL context variable for model selection from catalog
- Built-in Prometheus metrics endpoint (/metrics)
- Native health endpoint (/health)

### Removed

- Ollama inference wrapper and its registry dependency
- Nginx reverse proxy (TLS, auth, CORS now handled natively by llama-server)
- apache2-utils (htpasswd) dependency
- Port 80 HTTP redirect (only used temporarily for ACME challenge)
- Port 11434 Ollama API (replaced by direct llama-server on 8443)

## [1.1.0] - 2026-02-20

### Changed

- Replaced LocalAI with Ollama as inference backend (2x speed improvement: 3.9 -> 7.5 tok/s)
- Ollama ships AVX-512 optimized llama.cpp, eliminating manual backend compilation
- Systemd management via drop-in override instead of custom unit file
- Model configuration via Ollama Modelfile instead of LocalAI YAML
- Ollama installer manages its own system user and service unit

### Removed

- LocalAI binary download and llama-cpp backend installation
- Custom system user/group creation (Ollama installer handles this)
- GGUF file download (Ollama pulls models from its own registry)
- Custom systemd unit file generation

## [1.0.0] - 2026-02-16

### Added

- Initial release of SLM-Copilot appliance
- Devstral Small 2 24B (Q4_K_M) served by LocalAI v3.11.0 on CPU
- OpenAI-compatible API (chat completions with streaming)
- HTTPS reverse proxy with nginx and self-signed TLS
- Optional Let's Encrypt integration via ONEAPP_COPILOT_DOMAIN
- Basic authentication with auto-generated or user-supplied password
- Report file with connection details and aider setup guide
- SSH login banner with service status
- Configurable context variables: ONEAPP_COPILOT_AI_MODEL, ONEAPP_COPILOT_CONTEXT_SIZE, ONEAPP_COPILOT_CPU_THREADS, ONEAPP_COPILOT_API_PASSWORD, ONEAPP_COPILOT_TLS_DOMAIN
- Build-time model pre-warming with smoke tests
- Packer HCL2 build pipeline with cloud-init bootstrap
