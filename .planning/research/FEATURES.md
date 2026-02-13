# Feature Research

**Domain:** Self-hosted AI coding assistant (OpenNebula marketplace appliance)
**Researched:** 2026-02-13
**Confidence:** HIGH

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist. Missing these = product feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| OpenAI-compatible API endpoint | Cline, Continue.dev, and every coding IDE extension uses this protocol. Without it the appliance is useless. | LOW | LocalAI provides this natively at `/v1/chat/completions`. Streaming support included. |
| Streaming chat completions | Cline sends `stream: true` on every request. Non-streaming responses make the UX unbearable (no token-by-token feedback). | LOW | LocalAI supports streaming out of the box. Nginx must proxy WebSocket/chunked transfer correctly (`proxy_buffering off`). |
| Model pre-loaded and ready | Users import the appliance and expect it to work immediately. Downloading a 14 GB model on first boot is a deployment blocker. | MEDIUM | Bake the GGUF file into the QCOW2 image at build time. Place in `/models/` and reference via LocalAI YAML config. |
| TLS termination (self-signed) | Any API carrying auth tokens over plaintext is a non-starter for security-conscious European cloud admins. | LOW | Nginx generates a self-signed cert at first boot if no other TLS is configured. Standard pattern for OpenNebula appliances. |
| Basic authentication (API key) | Prevents unauthorized access. Cline sends `Authorization: Bearer <key>` on every request. | LOW | Two layers: LocalAI `--api-key` flag AND Nginx `basic_auth`. Use ONEAPP_COPILOT_API_KEY context variable. Generate random key if not provided. |
| Health check endpoint | Operators need to verify the service is running. OpenNebula, load balancers, and monitoring all poll health endpoints. | LOW | LocalAI exposes `/readyz` natively. Nginx can proxy it or add its own `/health` route. |
| Service report file | OpenNebula convention. After boot, `/etc/one-appliance/config` must show endpoint URL, credentials, and connection instructions. | LOW | Follow the one-apps pattern: write endpoint, API key, model name, and Cline config snippet to `ONE_SERVICE_REPORT`. |
| ONEAPP_* context variables | OpenNebula admins configure appliances through context variables, not SSH. This is the standard interface. | LOW | Define: `ONEAPP_COPILOT_API_KEY`, `ONEAPP_COPILOT_HOSTNAME`, `ONEAPP_COPILOT_TLS_MODE`, `ONEAPP_COPILOT_CONTEXT_SIZE`. |
| Systemd service management | The inference server must start on boot, restart on failure, and be controllable via `systemctl`. Standard Linux operations expectation. | LOW | LocalAI Docker container managed by systemd unit (or LocalAI binary directly under systemd). Auto-restart on failure. |
| Reconfigurability | OpenNebula appliances should support re-reading context variables on reboot/reconfigure without reimaging. | LOW | Set `ONE_SERVICE_RECONFIGURABLE=true`. Re-read ONEAPP_* vars in `service_configure()`. |

### Differentiators (Competitive Advantage)

Features that set the product apart. Not required, but valuable.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Let's Encrypt TLS automation | One context variable (`ONEAPP_COPILOT_HOSTNAME=code.example.com`) and the appliance auto-provisions a real certificate via certbot. Self-signed is table stakes; automated LE is a differentiator that makes the appliance production-ready out of the box. | MEDIUM | Requires certbot installed, port 80 reachable for ACME challenge. Fallback to self-signed if LE fails. Auto-renewal via systemd timer. |
| Cline connection instructions in report | The report file doesn't just show raw credentials -- it includes a copy-paste JSON snippet for Cline's `settings.json`. Zero-friction onboarding: import appliance, read report, paste config, code. | LOW | Template the JSON with actual endpoint URL, API key, and model ID. Include in both report file and MOTD. |
| Nginx rate limiting | CPU-only inference is slow (2-5 tok/s on a 24B model). Without rate limiting, one greedy client starves everyone else. Nginx `limit_req` and `limit_conn` protect the service. | LOW | Configure `limit_req_zone` (e.g., 2 req/s per IP) and `limit_conn_zone` (e.g., 2 concurrent connections per IP). Tunable via ONEAPP_* vars. |
| Configurable context window | Different use cases need different context sizes. Code review needs large context; quick completions need small context. Larger context = slower inference but more code understanding. | LOW | `ONEAPP_COPILOT_CONTEXT_SIZE` (default 8192, max 32768 for Devstral). LocalAI YAML `context_size` parameter. |
| European sovereign AI messaging | Explicit branding: "Your code never leaves your infrastructure. French-built model (Mistral/Devstral). EU-hosted inference." This resonates deeply with the Virt8ra audience. | LOW | Documentation, report file messaging, and appliance description text. No technical implementation needed -- pure positioning. |
| Model configuration via YAML | Advanced users can swap models by placing a new GGUF in `/models/` and editing the YAML config. Enables future model upgrades without rebuilding the image. | LOW | Document the pattern. Ship a clean `devstral.yaml` in `/models/`. Users can add configs for other models. |
| Inference performance tuning | Expose `ONEAPP_COPILOT_THREADS` to control CPU thread count for inference. Default to N-1 cores. Lets admins tune for their hardware. | LOW | Maps to LocalAI `--threads` flag or YAML `threads` parameter. |
| Request timeout protection | Long prompts on CPU can take minutes. Nginx `proxy_read_timeout` prevents clients from hanging indefinitely. Configurable via context variable. | LOW | `ONEAPP_COPILOT_TIMEOUT` (default 300s). Set in Nginx `proxy_read_timeout` and `proxy_send_timeout`. |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Multi-model support | "Let users pick from several models." | On CPU-only hardware, a 24B model already consumes most RAM. Loading multiple models causes OOM or thrashing. Model swapping adds latency (minutes to load). Appliance simplicity is the value proposition. | Ship one model, optimized. Document how advanced users can swap models via YAML config if they know what they are doing. |
| GPU passthrough | "GPU makes inference 10-50x faster." | Massively increases appliance complexity (driver compatibility, CUDA versions, PCI passthrough config). Target audience is CPU-only European cloud infrastructure. GPU support is a different product. | Explicitly position as CPU-only. Note in docs that GPU-enabled version is a possible future appliance. |
| Web UI / chat interface | "Add a ChatGPT-like web interface." | Scope creep. The product is a coding assistant API, not a chatbot. Web UIs (Open WebUI, etc.) add attack surface, maintenance burden, and confuse the value proposition. Cline IS the UI. | Document how to connect Cline and Continue.dev. If users want a web UI, they can deploy Open WebUI separately and point it at the API. |
| Model download on first boot | "Download the latest model at boot time instead of baking it in." | 14 GB download on first boot = 10-30 minute wait, requires internet access (breaks air-gapped deployments), and can fail silently. Defeats the "import and use" promise. | Bake the GGUF into the image. Provide documented instructions for replacing the model post-deployment. |
| RAG / document indexing | "Let the model search project documentation." | RAG requires embedding models, vector databases, document ingestion pipelines. Turns a simple appliance into a platform. Way beyond MVP scope. | Focus on the 256K context window of Devstral. Users paste relevant code into Cline, which handles context management. |
| User management / multi-tenancy | "Different API keys for different users with quotas." | LocalAI has no role separation -- API key is all-or-nothing admin access. Building multi-tenancy on top means adding a proxy layer (LiteLLM, custom auth). Massive scope increase. | Single API key via basic auth. Rate limiting per IP protects against abuse. For multi-user, deploy multiple appliance instances. |
| Code completion (non-chat) | "Support TabCompletion / FIM (fill-in-middle) like Copilot." | Requires a model fine-tuned for FIM tokens. Devstral is a chat/instruct model, not a completion model. Different API endpoint (`/v1/completions`), different client expectations. | Position as chat-based coding assistant via Cline. FIM completion is a different use case requiring a different model (e.g., StarCoder, CodeGemma). |
| Automatic model updates | "Check for new model versions and auto-update." | 14 GB downloads triggered automatically can fill disks, break running services, and introduce untested model versions. Appliance stability matters more than freshness. | Version-pin the model. Document manual update process. New model = new appliance image version. |

## Feature Dependencies

```
[ONEAPP_* Context Variables]
    |
    +--requires--> [Systemd Service Management]
    |                  |
    |                  +--requires--> [LocalAI Running with GGUF Model]
    |                                     |
    |                                     +--requires--> [Model Baked into Image]
    |
    +--requires--> [Nginx Reverse Proxy]
                       |
                       +--requires--> [TLS Termination (Self-Signed)]
                       |                  |
                       |                  +--enhances--> [Let's Encrypt Automation]
                       |
                       +--requires--> [Basic Authentication]
                       |
                       +--enhances--> [Rate Limiting]
                       |
                       +--enhances--> [Request Timeout Protection]
                       |
                       +--enhances--> [Health Check Endpoint]

[Service Report File]
    +--requires--> [ONEAPP_* Context Variables]
    +--enhances--> [Cline Connection Instructions]

[OpenAI-Compatible API]
    +--requires--> [LocalAI Running with GGUF Model]
    +--requires--> [Streaming Chat Completions]

[Configurable Context Window]
    +--requires--> [LocalAI YAML Config]
    +--requires--> [ONEAPP_* Context Variables]
```

### Dependency Notes

- **Nginx requires LocalAI running:** Nginx proxies to LocalAI's backend port (8080). Without LocalAI up, Nginx returns 502.
- **Let's Encrypt requires self-signed TLS first:** Self-signed is the fallback. LE is attempted only if hostname is set and port 80 is reachable.
- **Cline instructions require report file:** The JSON snippet is part of the report. Report must exist first.
- **Rate limiting enhances Nginx:** Configured as Nginx directives. No separate component needed.
- **Context window requires YAML config:** The `context_size` parameter lives in the LocalAI YAML model config file.

## MVP Definition

### Launch With (v1) -- Demo at Virt8ra GA

Minimum viable product for the Rotterdam demo. What's needed to show "import appliance, connect Cline, write code."

- [ ] **Devstral Small 2 Q4_K_M baked into QCOW2** -- The 14 GB GGUF model must be in the image. Zero-download deployment.
- [ ] **LocalAI running via systemd** -- Starts on boot, auto-restarts on failure, exposes OpenAI-compatible API.
- [ ] **Nginx reverse proxy with self-signed TLS** -- HTTPS endpoint for Cline connections. Generated at first boot.
- [ ] **Basic auth via API key** -- `ONEAPP_COPILOT_API_KEY` context variable. Random generation if not set.
- [ ] **Health check at /readyz** -- Nginx proxies to LocalAI `/readyz`. Proves the service is alive.
- [ ] **Service report file** -- Endpoint URL, API key, and Cline JSON config snippet in `/etc/one-appliance/config`.
- [ ] **ONEAPP_* context variables** -- At minimum: API_KEY, TLS_MODE, CONTEXT_SIZE, THREADS.
- [ ] **Streaming chat completions** -- `stream: true` works. Nginx configured with `proxy_buffering off`.
- [ ] **Reconfigurable** -- Reboot re-reads context variables without reimaging.

### Add After Validation (v1.x)

Features to add once core is working and demo feedback is collected.

- [ ] **Let's Encrypt automation** -- Add when users want production deployments with real certificates. Trigger: `ONEAPP_COPILOT_HOSTNAME` set to a real FQDN.
- [ ] **Nginx rate limiting** -- Add when multi-user scenarios emerge. Protects against greedy clients.
- [ ] **Request timeout protection** -- Add configurable `ONEAPP_COPILOT_TIMEOUT` for slow inference scenarios.
- [ ] **Inference thread tuning** -- `ONEAPP_COPILOT_THREADS` for admins who want to optimize CPU usage.
- [ ] **Model swap documentation** -- Documented procedure for replacing the GGUF with a different model.

### Future Consideration (v2+)

Features to defer until product-market fit is established.

- [ ] **Continue.dev support documentation** -- Second IDE extension. Same API, different config format.
- [ ] **Prometheus metrics export** -- LocalAI can expose metrics. Useful for monitoring, not critical for demo.
- [ ] **OneFlow service template** -- Multi-VM deployment template for teams (multiple copilot instances behind load balancer).
- [ ] **Different model variants** -- Ship multiple appliance images: one for Devstral (coding), one for Mistral Small (general).

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Model baked into image | HIGH | MEDIUM | P1 |
| LocalAI via systemd | HIGH | LOW | P1 |
| Nginx + self-signed TLS | HIGH | LOW | P1 |
| Basic auth (API key) | HIGH | LOW | P1 |
| Streaming completions | HIGH | LOW | P1 |
| Service report file | HIGH | LOW | P1 |
| ONEAPP_* context variables | HIGH | LOW | P1 |
| Health check endpoint | MEDIUM | LOW | P1 |
| Reconfigurability | MEDIUM | LOW | P1 |
| Cline JSON snippet in report | MEDIUM | LOW | P1 |
| Let's Encrypt automation | MEDIUM | MEDIUM | P2 |
| Nginx rate limiting | MEDIUM | LOW | P2 |
| Request timeout config | MEDIUM | LOW | P2 |
| Thread count tuning | LOW | LOW | P2 |
| Model swap documentation | LOW | LOW | P2 |
| Prometheus metrics | LOW | MEDIUM | P3 |
| Continue.dev docs | LOW | LOW | P3 |
| OneFlow template | LOW | HIGH | P3 |

**Priority key:**
- P1: Must have for launch (Virt8ra GA demo)
- P2: Should have, add when possible (post-demo polish)
- P3: Nice to have, future consideration

## Competitor Feature Analysis

| Feature | Tabby (self-hosted) | Ollama + Cline (DIY) | Our Approach (SLM-Copilot) |
|---------|---------------------|----------------------|---------------------------|
| Deployment | Docker Compose, requires GPU or beefy CPU | Manual: install Ollama, download model, configure Cline | One-click OpenNebula appliance import. Model pre-loaded. |
| Authentication | Built-in LDAP/SSO (enterprise) | None (localhost only) | Nginx basic auth + API key. Simple, effective. |
| TLS | User-configured reverse proxy | None (localhost HTTP) | Auto-generated self-signed + optional Let's Encrypt |
| IDE integration | Custom Tabby extension (VS Code, JetBrains) | OpenAI-compatible via Cline/Continue | OpenAI-compatible API. Works with any client. |
| Code completion | FIM (fill-in-middle) + chat | Chat only (model-dependent) | Chat-based via Cline. No FIM. |
| Model management | Built-in model registry | Ollama pull/run | Pre-baked GGUF. Manual swap documented. |
| First-time setup | 10-30 min (install, configure, download model) | 15-45 min (install Ollama, pull model, configure extension) | 5 min (import appliance, boot VM, paste config into Cline) |
| Data sovereignty | Yes (self-hosted) | Yes (local) | Yes (VM-contained, European model, no external calls) |
| CPU-only support | Yes (slow) | Yes (llama.cpp backend) | Yes (primary target). Positioned for CPU-only clouds. |
| Context providers | Git repos, docs, APIs (rich) | Cline handles context | Cline handles context. 256K context window for large codebases. |
| Target audience | Enterprise dev teams | Individual developers | European cloud admins deploying for dev teams |

**Our competitive advantage:** Zero-friction deployment on existing OpenNebula infrastructure. No Docker knowledge, no model downloads, no manual configuration. Import, boot, code. The appliance handles everything.

## Sources

- [LocalAI Features](https://localai.io/features/) -- Official feature list (HIGH confidence)
- [LocalAI Model Configuration](https://localai.io/advanced/model-configuration/) -- YAML config, context_size, threads (HIGH confidence)
- [LocalAI Getting Started](https://localai.io/basics/getting_started/) -- API key via `--api-key` flag (HIGH confidence)
- [Cline OpenAI Compatible Provider](https://docs.cline.bot/provider-config/openai-compatible) -- Base URL, API key, model ID fields (HIGH confidence)
- [Devstral Small 2 on HuggingFace](https://huggingface.co/mistralai/Devstral-Small-2-24B-Instruct-2512) -- 68% SWE-bench, 256K context (HIGH confidence)
- [Devstral Small 2 GGUF (bartowski)](https://huggingface.co/bartowski/mistralai_Devstral-Small-2-24B-Instruct-2512-GGUF) -- Q4_K_M = 14.3 GB (HIGH confidence)
- [Mistral Devstral 2 Announcement](https://mistral.ai/news/devstral-2-vibe-cli) -- Official capabilities and benchmarks (HIGH confidence)
- [Tabby Self-Hosted Coding Assistant](https://www.tabbyml.com/) -- Competitor feature reference (MEDIUM confidence)
- [LocalAI Health Check Issue #1566](https://github.com/mudler/LocalAI/issues/1566) -- `/readyz` endpoint behavior (HIGH confidence)
- [OpenNebula One-Apps](https://github.com/OpenNebula/one-apps/) -- Appliance patterns, report file convention (HIGH confidence)
- [LocalAI OpenAI Functions](https://localai.io/features/openai-functions/) -- Function calling with GGUF models (HIGH confidence)
- [LLM Self-Hosting and AI Sovereignty](https://www.glukhov.org/post/2026/02/llm-selfhosting-and-ai-sovereignty/) -- Sovereign AI trends (MEDIUM confidence)
- [Building Sovereign AI Factories](https://opennebula.io/blog/product/building-sovereign-ai-factories/) -- OpenNebula sovereign AI positioning (HIGH confidence)
- [LLM Gateway Patterns: Rate Limiting](https://collabnix.com/llm-gateway-patterns-rate-limiting-and-load-balancing-guide/) -- Nginx rate limiting for LLM APIs (MEDIUM confidence)

---
*Feature research for: Self-hosted AI coding assistant (OpenNebula marketplace appliance)*
*Researched: 2026-02-13*
