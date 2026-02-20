# Changelog

All notable changes to the SLM-Copilot appliance will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
- Report file with connection details and Cline VS Code setup guide
- SSH login banner with service status
- Configurable context variables: ONEAPP_COPILOT_CONTEXT_SIZE, ONEAPP_COPILOT_THREADS, ONEAPP_COPILOT_PASSWORD, ONEAPP_COPILOT_DOMAIN
- Build-time model pre-warming with smoke tests
- Packer HCL2 build pipeline with cloud-init bootstrap
