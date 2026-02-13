# Project Research Summary

**Project:** SLM-Copilot OpenNebula Appliance
**Domain:** CPU-only LLM inference appliance for AI coding assistance
**Researched:** 2026-02-13
**Confidence:** HIGH

## Executive Summary

This project builds a self-contained OpenNebula marketplace appliance for CPU-only LLM inference, specifically targeting European cloud providers who want sovereign AI coding assistance. The research reveals a proven technical path: LocalAI v3.11.0 with the llama-cpp backend running Devstral Small 2 24B (Q4_K_M quantization), fronted by Nginx for TLS termination and authentication. The model must be baked into the QCOW2 image during Packer build (14 GB GGUF file), not downloaded at runtime, to enable instant deployment.

The recommended approach follows the one-apps three-stage lifecycle pattern (install/configure/bootstrap) proven in the Flower FL appliance. All components run natively on Ubuntu 24.04 LTS without Docker, using systemd for service management. The critical path is: get LocalAI + model working first (Phase 1), then add security via Nginx (Phase 2), then package for marketplace deployment (Phase 3). Skip the install.sh script (it's broken as of Jan 2026) and download the pre-built binary directly from GitHub releases.

The main risks are: 14 GB model download timeouts during Packer build (use wget -c with resume support), CPU instruction set mismatches causing SIGILL crashes (test with minimal CPU models), and Nginx buffering destroying SSE streaming (requires 6 specific proxy directives). All are preventable with the patterns documented in research. The appliance targets 32 GB RAM / 16 vCPU as the sweet spot, delivering 3-5 tokens/second generation speed — slow but usable for coding assistance where you wait a few seconds per response.

## Key Findings

### Recommended Stack

LocalAI v3.11.0 is the clear choice for inference: it provides an OpenAI-compatible API, native GGUF support via llama-cpp, and single-binary deployment without Docker. The install.sh script is broken (GitHub issue #8032), so use direct binary download. Devstral Small 2 24B (December 2025 release) is the best open-source coding model at the 24B parameter count, achieving 68% on SWE-bench Verified with Apache 2.0 licensing. Q4_K_M quantization (14.3 GB file) is the industry-standard balance of quality vs size for CPU inference, losing less than 3% quality while reducing size by 75%.

**Core technologies:**
- **LocalAI v3.11.0**: OpenAI-compatible inference server — drop-in API replacement, native GGUF support, no Docker dependency, active development
- **Devstral Small 2 24B Q4_K_M**: Coding-focused SLM — best-in-class SWE performance at 24B params, Apache 2.0 license, purpose-built for agentic coding with tool-calling
- **Nginx 1.24.x**: Reverse proxy + TLS + auth — LocalAI has no built-in TLS (closed as "not planned"), Nginx handles all external-facing security concerns
- **Ubuntu 24.04 LTS**: Base OS — LTS support until 2029, standard OpenNebula marketplace base, proven pattern from Flower appliance
- **Packer v1.15.0 + QEMU plugin**: Image builder — proven KVM image build pattern, bake model into image for instant deployment

### Expected Features

From FEATURES.md, the MVP (v1 for Virt8ra GA demo) requires 9 table-stakes features that users absolutely expect, plus 5 differentiators that provide competitive advantage. The anti-features analysis warns against scope creep: no multi-model support (RAM constraints), no GPU passthrough (different product), no web UI (Cline is the interface), and no runtime model downloads (breaks instant deployment promise).

**Must have (table stakes):**
- OpenAI-compatible API endpoint — every IDE extension uses this protocol
- Streaming chat completions — Cline sends `stream: true` on every request
- Model pre-loaded and ready — 14 GB download on first boot is a deployment blocker
- TLS termination (self-signed) — any API carrying auth tokens over plaintext is a non-starter
- Basic authentication — prevents unauthorized access, Cline sends Bearer token
- Health check endpoint — operators need to verify service is running (`/readyz`)
- Service report file — OpenNebula convention, shows endpoint URL and credentials
- ONEAPP_* context variables — standard OpenNebula interface for configuration
- Systemd service management — starts on boot, restarts on failure

**Should have (competitive):**
- Let's Encrypt TLS automation — one context variable and the appliance auto-provisions real certificate
- Cline connection instructions in report — copy-paste JSON snippet for zero-friction onboarding
- Configurable context window — `ONEAPP_COPILOT_CONTEXT_SIZE` allows tuning for RAM vs code understanding
- European sovereign AI messaging — explicit branding that code never leaves infrastructure, French-built model
- Inference performance tuning — `ONEAPP_COPILOT_THREADS` for CPU thread count control

**Defer (v2+):**
- Continue.dev support documentation — same API, different config format
- Prometheus metrics export — useful for monitoring, not critical for demo
- OneFlow service template — multi-VM deployment for teams

### Architecture Approach

Single-VM appliance with three runtime components managed by systemd, built by Packer into a self-contained QCOW2 image. No containers, no orchestration. LocalAI binds to 127.0.0.1:8080 (loopback only) and serves the OpenAI-compatible API. Nginx binds to 0.0.0.0:443 and handles TLS termination, basic auth, CORS headers, and SSE streaming proxy to LocalAI. The GGUF model file (14.3 GB) is memory-mapped from disk at `/opt/local-ai/models/`. All configuration is generated at boot by the appliance script reading ONEAPP_* context variables.

**Major components:**
1. **LocalAI Engine** — OpenAI-compatible API server, llama-cpp backend orchestration, model management. Binds to localhost only. Pre-warms backend during Packer build to trigger the ~200 MB llama-cpp download.
2. **Nginx Reverse Proxy** — External-facing gateway. Handles TLS (self-signed default, Let's Encrypt optional), basic auth, CORS, SSE streaming (requires `proxy_buffering off` and 5 other directives), rate limiting, and request timeout protection (600s for slow CPU inference).
3. **Appliance Lifecycle Script** — Three-stage one-apps pattern: `service_install()` runs during Packer build (downloads binary and model), `service_configure()` runs every boot (reads ONEAPP_* vars, generates config files idempotently), `service_bootstrap()` starts services and waits for health checks.

### Critical Pitfalls

From PITFALLS.md, seven critical pitfalls can break the appliance if not addressed. All are preventable.

1. **LocalAI install.sh script is broken** — GitHub issue #8032 (Jan 2026) documents that install.sh produces misconfigured installations. Use direct binary download from GitHub releases instead.
2. **14 GB model download times out during Packer build** — HuggingFace CDN can be unstable for large files. Use `wget -c` (resume support) or pre-stage the model on the build host. Set Packer `ssh_timeout` to 30m minimum.
3. **LocalAI defaults context_size=512, silently truncates conversations** — The 512-token default is consumed by system prompt + 2-3 conversation turns. Model produces garbled output with no error. Always set `context_size` explicitly in model YAML (e.g., 32768 for Devstral).
4. **Nginx buffering destroys SSE streaming** — Nginx buffers responses by default. For LLM streaming, requires `proxy_buffering off`, `proxy_http_version 1.1`, `X-Accel-Buffering: no`, and generous timeouts (600s).
5. **TLS chicken-and-egg: Nginx won't start without certificate files** — Nginx validates all file paths at startup. Generate self-signed certificates during Packer build (service_install), not at first boot. Let's Encrypt runs after nginx is already up with self-signed cert.
6. **service_configure runs on every boot — non-idempotent operations break on reboot** — One-apps calls configure on every boot for reconfigurability. Every operation must be idempotent: use `>` not `>>`, `mkdir -p`, overwrite config files entirely. Test with reboot cycles.
7. **CPU instruction set mismatch causes SIGILL crashes** — LocalAI uses AVX/AVX2 SIMD. If binary is compiled for AVX2 but runs on CPU without AVX2 support, process crashes with SIGILL. Test with QEMU `-cpu qemu64` (minimal feature set) or download the "noavx" fallback binary.

## Implications for Roadmap

Based on combined research, the natural phase structure follows component dependencies and risk mitigation:

### Phase 1: Core Inference Engine
**Rationale:** LocalAI + model is the foundation everything else depends on. Get inference working before layering security. This phase de-risks the biggest unknowns: model download reliability, CPU compatibility, memory footprint, and inference speed validation.

**Delivers:**
- Appliance script skeleton with one-apps lifecycle (install/configure/bootstrap stubs)
- LocalAI v3.11.0 binary installation (direct download, not install.sh)
- Devstral Small 2 24B Q4_K_M GGUF download and verification (14.3 GB)
- Backend pre-warming during Packer build (triggers llama-cpp download)
- Model YAML configuration with explicit context_size=32768
- LocalAI systemd service unit
- Smoke test: inference request succeeds on localhost:8080

**Addresses features:**
- Model pre-loaded and ready (FEATURES.md table stakes)
- Health check endpoint (LocalAI `/readyz`)
- Systemd service management (FEATURES.md table stakes)

**Avoids pitfalls:**
- Pitfall 1: Uses binary download, not install.sh
- Pitfall 2: Implements resume-capable download with checksum verification
- Pitfall 3: Sets context_size explicitly in YAML
- Pitfall 7: Tests with minimal CPU model or uses fallback binary

### Phase 2: Security Layer
**Rationale:** Once inference works, add the external-facing security components. Nginx depends on having a working LocalAI backend to proxy to. This phase addresses the security gaps (no TLS, no auth) that make LocalAI unsafe to expose directly.

**Delivers:**
- Nginx installation and configuration
- Self-signed TLS certificate generation during Packer build
- Nginx reverse proxy config with SSE streaming support (6 directives)
- Basic auth setup via ONEAPP_COPILOT_PASSWORD
- Health check endpoint at /readyz (no auth required)
- CORS headers for browser-based clients
- Optional Let's Encrypt automation (ONEAPP_COPILOT_HOSTNAME trigger)

**Addresses features:**
- TLS termination (FEATURES.md table stakes)
- Basic authentication (FEATURES.md table stakes)
- Streaming chat completions through proxy (FEATURES.md table stakes)
- Let's Encrypt automation (FEATURES.md differentiator)

**Avoids pitfalls:**
- Pitfall 4: Implements all 6 nginx directives for SSE streaming
- Pitfall 5: Generates self-signed cert during Packer build, before nginx starts

### Phase 3: Configuration and Contextualization
**Rationale:** With inference and security working, add the OpenNebula integration layer. ONEAPP_* context variables must drive all configuration generation. This phase makes the appliance reconfigurable and self-documenting.

**Delivers:**
- ONEAPP_* context variable definitions in metadata
- service_configure reads context vars and generates all config files
- Idempotent configuration (safe for reboot)
- Service report file with endpoint URL, credentials, Cline JSON snippet
- Validation of all context variables (fail-fast on invalid input)
- Runtime tuning: context window size, thread count, timeout values

**Addresses features:**
- ONEAPP_* context variables (FEATURES.md table stakes)
- Service report file (FEATURES.md table stakes)
- Cline connection instructions (FEATURES.md differentiator)
- Configurable context window (FEATURES.md differentiator)
- Inference performance tuning (FEATURES.md differentiator)
- Reconfigurability (FEATURES.md table stakes)

**Avoids pitfalls:**
- Pitfall 6: All configure operations are idempotent, tested with reboot cycles

### Phase 4: Marketplace Packaging
**Rationale:** Only after all components work end-to-end should we package for distribution. This phase wraps the working appliance in marketplace metadata and performs final optimizations.

**Delivers:**
- Packer build definition (QEMU plugin, cloud-init seed ISO)
- Packer provisioning that runs service_install
- QCOW2 image compression (qemu-img convert -c)
- Marketplace metadata YAML (description, version, resources, context params)
- Test suite validating deployment scenarios
- Documentation: README, connection instructions, troubleshooting

**Addresses features:**
- (Packaging layer — enables all features to be deployed)

**Avoids pitfalls:**
- Comprehensive testing catches integration issues before marketplace submission

### Phase Ordering Rationale

**Dependency chain:**
- Nginx depends on LocalAI being available to proxy to → Phase 1 before Phase 2
- Context variables depend on components existing to configure → Phase 3 after Phases 1-2
- Packer packaging depends on all components working → Phase 4 last

**Risk mitigation:**
- Phase 1 de-risks the biggest unknowns early (model size, CPU speed, compatibility)
- Phase 2 addresses security before testing with real clients
- Phase 3 ensures production-ready configuration before packaging
- Phase 4 only happens when everything is proven to work

**Pitfall avoidance:**
- Pitfalls 1-3 are addressed in Phase 1 (foundation must be solid)
- Pitfall 4-5 are addressed in Phase 2 (security layer correctness)
- Pitfall 6 is addressed in Phase 3 (configuration idempotency)
- Pitfall 7 is verified throughout all phases (CPU compatibility testing)

**Component grouping:**
- Phase 1: Inference engine (LocalAI + model + systemd)
- Phase 2: Security gateway (Nginx + TLS + auth)
- Phase 3: OpenNebula integration (context vars + report file)
- Phase 4: Deployment packaging (Packer + metadata)

### Research Flags

**Phases needing deeper research during planning:**
- **Phase 2 (Security Layer):** Let's Encrypt integration with OpenNebula VMs may have edge cases (DNS propagation timing, port 80 firewall rules). Standard certbot docs may not cover the VM context.

**Phases with standard patterns (skip research-phase):**
- **Phase 1 (Core Inference Engine):** Well-documented LocalAI installation, standard systemd patterns, proven Packer provisioning from Flower appliance.
- **Phase 3 (Configuration):** One-apps lifecycle is documented and proven in Flower appliance. Direct code reuse possible.
- **Phase 4 (Marketplace Packaging):** Packer QEMU builder is well-documented, marketplace metadata format is standardized, Flower appliance provides reference.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Official LocalAI docs verified (v3.11.0 latest as of Feb 7 2026), Devstral 2 on HuggingFace with clear specs, bartowski GGUF quantizations are standard, Ubuntu 24.04 LTS and Nginx are proven. Install script bug confirmed via GitHub issue #8032. |
| Features | HIGH | Feature expectations derived from Cline documentation (OpenAI-compatible API required), OpenNebula appliance conventions (context vars, report file), and competitive analysis vs Tabby/Ollama. Anti-features validated against RAM constraints (24B model needs most of 32 GB). |
| Architecture | HIGH | Loopback-only backend pattern is security best practice. Three-stage one-apps lifecycle proven in Flower appliance (direct code examination). Nginx SSE streaming config verified across multiple sources (DigitalOcean, objectgraph.com, medium articles all agree on same 6 directives). |
| Pitfalls | HIGH | Pitfall 1 (broken install.sh) verified via GitHub issue #8032 with maintainer acknowledgment. Pitfalls 3-6 verified via official LocalAI docs and GitHub issues (#868, #7426, #1295, #4576). Pitfall 7 (CPU crashes) verified via issues #6348, #3367, and v3.10.0 release notes. Pitfall 2 (download timeouts) is MEDIUM confidence based on HuggingFace community reports. |

**Overall confidence:** HIGH

Research sources are primarily official documentation (LocalAI, Nginx, Packer, OpenNebula) and verified GitHub issues with maintainer responses. The architecture patterns are proven in the Flower appliance codebase (direct examination). The only MEDIUM-confidence element is HuggingFace download reliability, which varies by network conditions but is mitigated with resume-capable downloads.

### Gaps to Address

**Model performance on target hardware:** Research provides CPU inference benchmarks (3.66 tok/s for comparable 24B Q4_K_M model) but this is from a laptop with partial CPU. Production performance on 16 vCPU VM needs empirical validation during Phase 1. **Mitigation:** Run inference benchmark as part of Phase 1 testing; document actual tok/s in appliance metadata.

**Let's Encrypt timing in OpenNebula VMs:** Standard certbot documentation assumes stable DNS and immediate port 80 reachability. OpenNebula VMs may have DNS propagation delays or firewall rules that block port 80 initially. **Mitigation:** Phase 2 should test Let's Encrypt flow with realistic OpenNebula network configurations; provide clear error messages if cert acquisition fails; ensure self-signed fallback always works.

**RAM footprint with full context window:** Research calculates 14.3 GB model + ~4-8 GB KV cache at 128K context = 18-22 GB before OS overhead. On 32 GB VM this is tight. **Mitigation:** Default to 32K context (safer), document RAM requirements clearly in marketplace metadata, add validation in service_configure that warns if estimated RAM exceeds available.

**CPU compatibility across OpenNebula deployments:** Different OpenNebula clouds may use different default QEMU CPU models. Some expose AVX2, some don't. **Mitigation:** Either (a) document CPU_MODEL=host requirement in appliance metadata, or (b) use the noavx fallback binary and accept slower performance. Test during Phase 1 with qemu64 minimal CPU model.

## Sources

### Primary (HIGH confidence)
- [LocalAI Official Documentation](https://localai.io/) — installation, configuration, CLI reference, model YAML schema
- [LocalAI GitHub Issues](https://github.com/mudler/LocalAI/issues) — #8032 (install.sh broken), #1295 (no TLS), #4576 (CORS+API key bug), #868 (context crash), #7426 (context_size ignored), #6348 & #3367 (AVX crashes)
- [LocalAI GitHub Releases](https://github.com/mudler/LocalAI/releases) — v3.11.0 (Feb 7 2026), v3.10.0 AVX crash fixes
- [Mistral Devstral Small 2 on HuggingFace](https://huggingface.co/mistralai/Devstral-Small-2-24B-Instruct-2512) — 256K context, 68% SWE-bench Verified, Apache 2.0, Dec 2025
- [bartowski GGUF Quantizations](https://huggingface.co/bartowski/mistralai_Devstral-Small-2-24B-Instruct-2512-GGUF) — Q4_K_M = 14.3 GB
- [Cline Documentation](https://docs.cline.bot/provider-config/openai-compatible) — OpenAI-compatible provider config
- [Nginx Official Documentation](https://nginx.org/en/docs/) — proxy module, SSL module
- [Packer Documentation](https://developer.hashicorp.com/packer) — QEMU builder, v1.15.0
- [OpenNebula one-apps GitHub](https://github.com/OpenNebula/one-apps/) — appliance framework patterns
- Flower FL appliance codebase (direct code examination) — one-apps lifecycle, systemd patterns

### Secondary (MEDIUM confidence)
- [Nginx AI Proxy Blog](https://blog.nginx.org/blog/using-nginx-as-an-ai-proxy) — SSE streaming configuration
- [DigitalOcean SSE Nginx Guide](https://www.digitalocean.com/community/questions/nginx-optimization-for-server-sent-events-sse) — proxy_buffering off pattern
- [objectgraph.com SSE Guide](https://objectgraph.com/blog/optimizing-sse-nginx-streaming/) — comprehensive proxy directives
- [Medium: SSE Troubleshooting](https://medium.com/@wang645788/troubleshooting-server-sent-events-sse-in-a-multi-service-architecture-5084ce155ea0) — proxy_http_version 1.1 requirement
- [LLM Quantization Guide](https://localaimaster.com/blog/quantization-explained) — Q4_K_M quality retention
- [24B LLM CPU Benchmark](https://aimuse.blog/article/2025/06/13/the-real-world-speed-of-ai-benchmarking-a-24b-llm-on-local-hardware-vs-high-end-cloud-gpus) — 3.66 tok/s (comparable model)
- [HuggingFace Download Instability Discussion](https://discuss.huggingface.co/t/download-instability-disconnects/137529) — CDN issues with large files
- [Tabby Self-Hosted](https://www.tabbyml.com/) — competitor feature reference

### Tertiary (LOW confidence)
- Community reports of Ollama + Cline DIY setups — configuration complexity anecdotes
- OpenNebula community forum discussions on marketplace appliances — user expectations

---
*Research completed: 2026-02-13*
*Ready for roadmap: yes*
