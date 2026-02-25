# Changelog

All notable changes to the SLM-Copilot appliance will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [2.1.0] - 2026-02-25

### Added

- Optional LiteLLM load balancing across multiple SLM-Copilot VMs via ONEAPP_COPILOT_LB_BACKENDS
- Least-busy routing, automatic failover (2 fails = 30s cooldown), and cross-site distribution
- LiteLLM proxy systemd unit (slm-copilot-proxy.service) with TLS and master_key auth
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
