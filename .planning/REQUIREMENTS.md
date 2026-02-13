# Requirements: SLM-Copilot

**Defined:** 2026-02-13
**Core Value:** One-click deployment of a sovereign, CPU-only AI coding copilot from the OpenNebula marketplace

## v1 Requirements

Requirements for the Virt8ra General Assembly demo (Rotterdam, March 2026). Each maps to roadmap phases.

### Inference Engine

- [ ] **INFER-01**: LocalAI serves Devstral Small 2 24B (Q4_K_M) via OpenAI-compatible API at /v1/chat/completions
- [ ] **INFER-02**: Streaming chat completions work with SSE (stream: true), tokens delivered incrementally
- [ ] **INFER-03**: Model weights (14 GB GGUF) are baked into the QCOW2 image, no runtime download needed
- [ ] **INFER-04**: LocalAI runs as a systemd service that starts on boot and auto-restarts on failure
- [ ] **INFER-05**: Health check endpoint (/readyz) returns 200 when model is loaded and ready
- [ ] **INFER-06**: Context window size is configurable via ONEAPP_COPILOT_CONTEXT_SIZE (default 32768)
- [ ] **INFER-07**: CPU thread count is configurable via ONEAPP_COPILOT_THREADS (default auto-detect)
- [ ] **INFER-08**: LocalAI binds to 127.0.0.1:8080 only, never exposed to the network directly
- [ ] **INFER-09**: llama-cpp backend is pre-downloaded during Packer build (no first-request download delay)

### Security & Access

- [ ] **SEC-01**: Nginx terminates TLS with self-signed certificate generated at first boot
- [ ] **SEC-02**: Nginx enforces basic authentication on all API endpoints (except /health)
- [ ] **SEC-03**: If no password is provided via context, a random 16-char alphanumeric password is auto-generated
- [ ] **SEC-04**: CORS headers are set on all responses (Access-Control-Allow-Origin, Methods, Headers)
- [ ] **SEC-05**: OPTIONS preflight requests return 204 with CORS headers, no authentication required
- [ ] **SEC-06**: Let's Encrypt certificate is auto-provisioned when ONEAPP_COPILOT_DOMAIN is set to a valid FQDN
- [ ] **SEC-07**: Let's Encrypt falls back to self-signed if certbot fails (port 80 blocked, DNS not resolving)
- [ ] **SEC-08**: Nginx proxy supports SSE streaming (proxy_buffering off, proxy_http_version 1.1, 600s timeout)
- [ ] **SEC-09**: HTTP (port 80) redirects to HTTPS (port 443) when TLS is enabled

### OpenNebula Integration

- [ ] **ONE-01**: All configuration is driven by ONEAPP_* context variables with sensible defaults
- [ ] **ONE-02**: Service report file at /etc/one-appliance/config shows endpoint URL, credentials, model, and status
- [ ] **ONE-03**: service_configure() is fully idempotent - running multiple times produces identical results
- [ ] **ONE-04**: Appliance follows the one-apps three-stage lifecycle (install/configure/bootstrap)
- [ ] **ONE-05**: Report file includes a copy-paste Cline JSON config snippet for VS Code settings.json
- [ ] **ONE-06**: Appliance description and marketplace metadata include European sovereign AI messaging
- [ ] **ONE-07**: All appliance operations log to /var/log/one-appliance/slm-copilot.log with timestamps
- [ ] **ONE-08**: One-appliance banner is printed on boot when services are ready

### Build & Distribution

- [ ] **BUILD-01**: Packer HCL2 definition builds a compressed QCOW2 from Ubuntu 24.04 cloud image
- [ ] **BUILD-02**: Community Marketplace YAML metadata follows the marketplace-community format
- [ ] **BUILD-03**: Post-deployment test script validates HTTPS, auth, health, model listing, chat completion, and streaming
- [ ] **BUILD-04**: Manual build guide documents step-by-step image creation without Packer
- [ ] **BUILD-05**: Makefile provides build, test, checksum, clean, and lint targets
- [ ] **BUILD-06**: Build wrapper script checks dependencies, downloads base image, runs Packer, generates checksums
- [ ] **BUILD-07**: All bash scripts pass shellcheck with no warnings
- [ ] **BUILD-08**: Complete README documents architecture, quick start, configuration, Cline setup, troubleshooting, and performance

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Extended IDE Support

- **IDE-01**: Continue.dev connection documentation and configuration examples
- **IDE-02**: JetBrains AI Assistant integration documentation

### Monitoring

- **MON-01**: Prometheus metrics endpoint for inference latency, request count, model load status
- **MON-02**: Grafana dashboard template for appliance monitoring

### Scaling

- **SCALE-01**: OneFlow service template for multi-VM copilot pool behind load balancer
- **SCALE-02**: Nginx rate limiting per IP (configurable via ONEAPP_* context variable)

## Out of Scope

| Feature | Reason |
|---------|--------|
| GPU passthrough / CUDA | CPU-only by design - the entire demo narrative. Different product. |
| Docker / Kubernetes | Bare-metal installation, no container runtime. Simplicity is the value. |
| Multiple models simultaneously | RAM constraints (24B model uses most of 32 GB). Single model appliance. |
| Web UI / chat interface | Cline is the UI. Web UIs add attack surface and scope creep. |
| Runtime model download | Breaks instant deployment promise. 14 GB on first boot is unacceptable. |
| RAG / document indexing | Requires embedding models, vector DB. Way beyond MVP scope. |
| Multi-user / multi-tenant | LocalAI has no role separation. Deploy multiple instances for teams. |
| FIM / tab completion | Devstral is chat/instruct model, not completion model. Different use case. |
| Automatic model updates | 14 GB auto-downloads break stability. New model = new image version. |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| INFER-01 | Phase 1 | Pending |
| INFER-02 | Phase 1 | Pending |
| INFER-03 | Phase 1 | Pending |
| INFER-04 | Phase 1 | Pending |
| INFER-05 | Phase 1 | Pending |
| INFER-06 | Phase 1 | Pending |
| INFER-07 | Phase 1 | Pending |
| INFER-08 | Phase 1 | Pending |
| INFER-09 | Phase 1 | Pending |
| SEC-01 | Phase 2 | Pending |
| SEC-02 | Phase 2 | Pending |
| SEC-03 | Phase 2 | Pending |
| SEC-04 | Phase 2 | Pending |
| SEC-05 | Phase 2 | Pending |
| SEC-06 | Phase 2 | Pending |
| SEC-07 | Phase 2 | Pending |
| SEC-08 | Phase 2 | Pending |
| SEC-09 | Phase 2 | Pending |
| ONE-01 | Phase 3 | Pending |
| ONE-02 | Phase 3 | Pending |
| ONE-03 | Phase 3 | Pending |
| ONE-04 | Phase 3 | Pending |
| ONE-05 | Phase 3 | Pending |
| ONE-06 | Phase 3 | Pending |
| ONE-07 | Phase 3 | Pending |
| ONE-08 | Phase 3 | Pending |
| BUILD-01 | Phase 4 | Pending |
| BUILD-02 | Phase 4 | Pending |
| BUILD-03 | Phase 4 | Pending |
| BUILD-04 | Phase 4 | Pending |
| BUILD-05 | Phase 4 | Pending |
| BUILD-06 | Phase 4 | Pending |
| BUILD-07 | Phase 4 | Pending |
| BUILD-08 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 34 total
- Mapped to phases: 34
- Unmapped: 0 ✓

---
*Requirements defined: 2026-02-13*
*Last updated: 2026-02-13 after initial definition*
