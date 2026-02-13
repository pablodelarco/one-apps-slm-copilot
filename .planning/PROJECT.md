# SLM-Copilot: Sovereign AI Coding Assistant for OpenNebula

## What This Is

A production-ready OpenNebula marketplace appliance that packages a self-contained AI coding assistant running entirely on CPU. It uses LocalAI to serve Mistral's Devstral Small 2 (24B parameter, Q4_K_M quantization) coding model, fronted by Nginx with TLS and basic authentication. Developers connect from VS Code with the Cline extension and get a fully sovereign, open-source coding copilot. No GPU required.

## Core Value

One-click deployment of a sovereign, CPU-only AI coding copilot from the OpenNebula marketplace - import, instantiate, code.

## Requirements

### Validated

(None yet - ship to validate)

### Active

- [ ] Complete OpenNebula marketplace appliance following one-apps conventions (three-stage service script)
- [ ] LocalAI serves Devstral Small 2 (24B, Q4_K_M) via OpenAI-compatible API on localhost:8080
- [ ] Model weights baked into QCOW2 image during Packer build (~14 GB GGUF)
- [ ] Nginx reverse proxy with TLS termination (self-signed + Let's Encrypt), basic auth, and CORS
- [ ] ONEAPP_* context variables configure all runtime behavior
- [ ] Report file at /etc/one-appliance/config shows endpoint, credentials, and status
- [ ] Packer build definition produces compressed QCOW2 image from Ubuntu 24.04 cloud image
- [ ] Community Marketplace YAML metadata for submission
- [ ] Build scripts (Packer wrapper, manual build guide)
- [ ] Post-deployment validation/test script
- [ ] Complete documentation (README) with Cline connection guide
- [ ] All bash scripts shellcheck-clean with set -euo pipefail

### Out of Scope

- GPU drivers/CUDA - CPU-only by design, the whole point of the demo
- Docker/Kubernetes - bare-metal installation, no container orchestration
- Multiple model support - single model (Devstral Small 2) baked in
- Web UI for LocalAI - API-only, Cline is the interface
- Federation orchestration - this is a single-VM appliance, federation is at the OpenNebula layer

## Context

**Demo context:** Primary demo for the Virt8ra General Assembly in Rotterdam (March 19-20, 2026). Virt8ra is a federation of 10 OpenNebula zones across Europe demonstrating a "European Virtual Hyperscaler." Narrative: "European Copilot on the Virtual Hyperscaler" - proving AI coding assistance works on CPU, sovereignty matters.

**Demo flow:**
1. Show Virt8ra federation dashboard (10 zones)
2. Deploy SLM-Copilot from shared marketplace to a specific zone (e.g., Paris)
3. Open VS Code + Cline, connect to deployed instance
4. Live coding: analyze codebase, refactor, generate tests, fix bugs
5. Sovereignty pitch: same appliance in any zone, code stays in-jurisdiction

**Key messaging:**
- "Not all AI needs GPU" - 24B model on CPU, practical inference speed
- "100% sovereign" - Mistral (France) + OpenNebula (Spain), Apache 2.0 everywhere
- "One-click deployment" - marketplace to running copilot in minutes
- "100% open-source" - model, inference server, proxy, cloud orchestrator

**OpenNebula appliance conventions (from one-apps):**
- Three-stage service script: service_install() (build-time), service_configure() (every boot), service_bootstrap() (first boot)
- ONEAPP_* context variables for all configuration
- Report file at /etc/one-appliance/config
- Logging to /var/log/one-appliance/
- Marketplace submission via YAML metadata + PR to marketplace-community

**LocalAI specifics:**
- Pre-built binary from GitHub releases (v3.7.0+, install script is broken per issue #8032)
- Model config via YAML file in models directory + GGUF file
- Backend: llama-cpp for GGUF inference
- Built-in API key auth (--api-keys) and CORS (--cors) exist but CORS+API key has known bug (#4576)
- No built-in TLS (closed as "not planned" #1295)
- Bind address control via --address flag

**Devstral Small 2 model:**
- 24B parameters, coding-specialized (68% SWE-bench verified)
- Q4_K_M quantization: ~14 GB on disk, ~14 GB RAM at runtime
- 128K token context window
- European origin: Mistral AI (Paris), Apache 2.0 license
- Officially partnered with Cline VS Code extension
- CPU inference: 5-15 tok/s on 32-core with AVX-512
- GGUF source: bartowski/mistralai_Devstral-Small-2-24B-Instruct-2512-GGUF on HuggingFace

**Author:** Pablo del Arco, Cloud-Edge Innovation Engineer at OpenNebula Systems (Valencia, Spain)

## Constraints

- **Tech stack**: LocalAI + Devstral Small 2 + Nginx + OpenNebula context. Nothing else.
- **No GPU**: CPU-only inference, no CUDA/GPU drivers anywhere
- **No Docker**: Bare-metal installation, no container runtime
- **Image size**: Target QCOW2 20-25 GB (OS ~2 GB + model ~14 GB + packages ~1 GB + headroom)
- **Runtime resources**: 32 GB RAM minimum (14 GB model + overhead), 16 vCPU minimum, 50 GB disk
- **Compatibility**: OpenNebula 7.0+, KVM hypervisor, x86_64, any OpenNebula cloud
- **Deadline**: Demo-ready by March 19, 2026 (Virt8ra GA, Rotterdam)
- **License**: Apache 2.0 for appliance, Apache 2.0 for Devstral, MIT for LocalAI, BSD for Nginx

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| LocalAI over Ollama | Better GGUF model management, OpenAI-compatible API native, more configurable | -- Pending |
| Pre-built binary install | Install script broken (#8032), binary is single file, easy to manage | -- Pending |
| Model baked into image | Instant deploy, no internet needed at runtime, predictable image size | -- Pending |
| Nginx for TLS + auth + CORS | LocalAI has no TLS (#1295), CORS+API key bug (#4576). Nginx handles all external concerns cleanly. | -- Pending |
| LocalAI on localhost:8080 | Default port, never exposed to network. Nginx proxies all external traffic. | -- Pending |
| Self-signed + Let's Encrypt | Self-signed for quick deploy, Let's Encrypt for production with FQDN | -- Pending |
| GGUF from bartowski/HuggingFace | Well-maintained quantizations, Q4_K_M balance of quality and size | -- Pending |

---
*Last updated: 2026-02-13 after initialization*
