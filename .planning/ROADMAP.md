# Roadmap: SLM-Copilot

## Overview

This roadmap delivers a production-ready OpenNebula marketplace appliance for sovereign AI coding assistance. The build progresses through four phases following component dependencies: get inference working first (LocalAI + Devstral model), add the security gateway (Nginx + TLS + auth), wire up OpenNebula integration (context variables + report file + lifecycle), then package everything for marketplace distribution (Packer build + tests + docs). Each phase delivers a coherent, verifiable capability that the next phase builds on.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3, 4): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Inference Engine** - LocalAI serves Devstral Small 2 on CPU with streaming, health checks, and systemd management ✓ (2026-02-14)
- [x] **Phase 2: Security & Access** - Nginx reverse proxy with TLS, authentication, CORS, and SSE streaming support ✓ (2026-02-14)
- [x] **Phase 3: OpenNebula Integration** - Context variable-driven configuration, report file, idempotent lifecycle, and logging ✓ (2026-02-14)
- [x] **Phase 4: Build & Distribution** - Packer image build, test suite, marketplace metadata, and documentation ✓ (2026-02-14)

## Phase Details

### Phase 1: Inference Engine
**Goal**: A developer can send a chat completion request to localhost:8080 and receive streaming tokens from Devstral Small 2 24B running on CPU
**Depends on**: Nothing (first phase)
**Requirements**: INFER-01, INFER-02, INFER-03, INFER-04, INFER-05, INFER-06, INFER-07, INFER-08, INFER-09
**Success Criteria** (what must be TRUE):
  1. `curl localhost:8080/v1/chat/completions` with a coding question returns a valid JSON response with model-generated content
  2. `curl localhost:8080/v1/chat/completions` with `"stream": true` returns incrementally delivered SSE chunks ending with `[DONE]`
  3. `curl localhost:8080/readyz` returns HTTP 200 when the model is loaded and ready for inference
  4. After a VM reboot, the LocalAI systemd service starts automatically and recovers from a simulated crash (kill -9) within 30 seconds
  5. LocalAI is unreachable from any network interface except 127.0.0.1 (verified by attempting connection from external IP)
**Plans:** 3 plans

Plans:
- [x] 01-01-PLAN.md — Appliance script skeleton and LocalAI binary installation
- [x] 01-02-PLAN.md — Model download, configuration, backend pre-warming, and systemd service
- [x] 01-03-PLAN.md — Context variable validation, smoke tests, and shellcheck compliance

### Phase 2: Security & Access
**Goal**: A developer can connect to the appliance over HTTPS with authentication and receive streaming code completions through the Nginx proxy
**Depends on**: Phase 1
**Requirements**: SEC-01, SEC-02, SEC-03, SEC-04, SEC-05, SEC-06, SEC-07, SEC-08, SEC-09
**Success Criteria** (what must be TRUE):
  1. `curl -k https://<vm-ip>/v1/chat/completions` with valid basic auth credentials returns model output; without credentials returns HTTP 401
  2. `curl -k https://<vm-ip>/v1/chat/completions` with `"stream": true` delivers SSE tokens incrementally (no buffering delay, proxy_buffering off verified)
  3. An OPTIONS preflight request to any API endpoint returns HTTP 204 with CORS headers and requires no authentication
  4. When ONEAPP_COPILOT_DOMAIN is set to a valid FQDN with DNS and port 80 open, the appliance serves a Let's Encrypt certificate; when certbot fails, it falls back to self-signed without breaking the service
  5. `curl http://<vm-ip>/anything` redirects to `https://<vm-ip>/anything` with HTTP 301
**Plans**: 2 plans

Plans:
- [x] 02-01: Nginx installation, self-signed TLS, and reverse proxy with SSE streaming
- [x] 02-02: Basic auth, CORS headers, Let's Encrypt automation, and HTTP redirect

### Phase 3: OpenNebula Integration
**Goal**: The appliance is fully configurable via OpenNebula context variables, self-documenting via the report file, and survives reboot cycles without configuration drift
**Depends on**: Phase 2
**Requirements**: ONE-01, ONE-02, ONE-03, ONE-04, ONE-05, ONE-06, ONE-07, ONE-08
**Success Criteria** (what must be TRUE):
  1. Changing any ONEAPP_* context variable and rebooting the VM produces the corresponding configuration change (e.g., new password, different context window size) without manual intervention
  2. `cat /etc/one-appliance/config` shows the endpoint URL, current credentials, model name, service status, and a copy-paste Cline JSON snippet for VS Code settings.json
  3. Rebooting the VM three times in a row produces identical service behavior each time (idempotent configure)
  4. All appliance operations (install, configure, bootstrap) are logged to `/var/log/one-appliance/slm-copilot.log` with timestamps
  5. SSH login to the VM displays a one-appliance banner showing service status and connection information
**Plans:** 2 plans

Plans:
- [x] 03-01-PLAN.md — Dedicated logging (log_copilot wrapper, COPILOT_LOG), replace all msg calls
- [x] 03-02-PLAN.md — Report file, Cline snippet, SSH banner, and marketplace metadata YAML

### Phase 4: Build & Distribution
**Goal**: A new user can build the QCOW2 image from source, deploy it to any OpenNebula cloud, validate it works, and submit it to the community marketplace
**Depends on**: Phase 3
**Requirements**: BUILD-01, BUILD-02, BUILD-03, BUILD-04, BUILD-05, BUILD-06, BUILD-07, BUILD-08
**Success Criteria** (what must be TRUE):
  1. Running `make build` on a clean machine with Packer and QEMU installed produces a compressed QCOW2 image containing Ubuntu 24.04 + LocalAI + Devstral model + Nginx + appliance scripts
  2. The post-deployment test script (`make test`) validates HTTPS connectivity, authentication, health endpoint, model listing, chat completion, and streaming against a running instance and reports pass/fail for each check
  3. All bash scripts in the repository pass `shellcheck` with zero warnings (`make lint` exits 0)
  4. The README documents architecture, quick start, all ONEAPP_* variables, Cline connection setup (with screenshots or JSON snippets), troubleshooting steps, and performance expectations
  5. Community marketplace YAML metadata is complete and follows the marketplace-community repository format, ready for PR submission
**Plans:** 3 plans

Plans:
- [x] 04-01-PLAN.md — Packer HCL definition, cloud-init, provisioner scripts, build wrapper script, and Makefile
- [x] 04-02-PLAN.md — Post-deployment test script and shellcheck compliance
- [x] 04-03-PLAN.md — README documentation, manual build guide, and marketplace YAML finalization

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Inference Engine | 3/3 | ✓ Complete | 2026-02-14 |
| 2. Security & Access | 2/2 | ✓ Complete | 2026-02-14 |
| 3. OpenNebula Integration | 2/2 | ✓ Complete | 2026-02-14 |
| 4. Build & Distribution | 3/3 | ✓ Complete | 2026-02-14 |
