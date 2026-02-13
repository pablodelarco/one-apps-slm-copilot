# Pitfalls Research

**Domain:** CPU-only LLM inference appliance (OpenNebula marketplace)
**Researched:** 2026-02-13
**Confidence:** HIGH (combination of official docs, verified GitHub issues, and author's direct OpenNebula appliance experience)

## Critical Pitfalls

### Pitfall 1: LocalAI Install Script Is Broken -- Must Use Manual Binary

**What goes wrong:**
The official `install.sh` script at localai.io/installation/linux/ produces broken or misconfigured installations. Issue #8032 (opened January 2026) documents this, and the maintainer (mudler) confirmed the script should remain disabled until fixed. Users report the script-installed binary doesn't work properly, particularly with backend detection and configuration.

**Why it happens:**
LocalAI is undergoing heavy internal changes (v3.10-3.11 release cycle). The install script hasn't kept pace with build system changes, binary naming conventions, and backend packaging.

**How to avoid:**
Download the pre-built binary directly from GitHub releases (`https://github.com/mudler/LocalAI/releases`). For CPU-only deployment, select the binary matching the host's CPU instruction set (AVX2, AVX-only, or fallback/no-AVX). Pin a specific version (e.g., v2.25.0 or latest stable) and download with checksum verification during the Packer build.

```bash
# Example: download specific CPU-only binary during Packer build
LOCALAI_VERSION="2.25.0"
ARCH="amd64"
curl -L -o /usr/local/bin/local-ai \
  "https://github.com/mudler/LocalAI/releases/download/v${LOCALAI_VERSION}/local-ai-Linux-${ARCH}"
chmod +x /usr/local/bin/local-ai
```

**Warning signs:**
- `local-ai` binary exits immediately or segfaults on startup
- "backend not found: llama-cpp" errors in logs
- Model loading fails with "rpc error: code = Unavailable"

**Phase to address:** Phase 1 (Base Image Build) -- binary installation is the foundation everything else depends on.

**Confidence:** HIGH -- verified via GitHub issue #8032, multiple user reports, maintainer acknowledgment.

---

### Pitfall 2: GGUF Model Download Fails During Packer Build (14 GB Timeout)

**What goes wrong:**
Downloading 4-8 GB GGUF model files from HuggingFace during a Packer provisioning step can fail mid-transfer due to network timeouts, HuggingFace rate limiting, or Packer SSH session timeout. A partial download wastes the entire 30-60 minute build. The Packer SSH timeout (default 5m) may kill the session before the download completes.

**Why it happens:**
HuggingFace CDN can be unstable for large files (user reports of disconnects on files >2 GB). Packer's `ssh_timeout` controls initial connection but `ssh_handshake_attempts` and provisioner timeouts can still kill long-running downloads. The QEMU VM may also have limited bandwidth through the virtual NIC.

**How to avoid:**
1. Use `wget -c` (resume-capable) or `curl -C -` for downloads so partial downloads can resume.
2. Set Packer `ssh_timeout` to at least "30m" and use `-on-error=ask` during development.
3. Download models to the Packer host first, then `scp`/`rsync` them into the VM (avoids double-network-hop issues).
4. Verify file integrity with SHA256 checksums after download.
5. Consider pre-downloading models and injecting them via Packer `file` provisioner.

```bash
# Resume-capable download with checksum verification
wget -c -O /opt/localai/models/model.gguf \
  "https://huggingface.co/TheBloke/Phi-3-mini-4k-instruct-GGUF/resolve/main/Phi-3-mini-4k-instruct-Q4_K_M.gguf"

# Verify checksum
echo "EXPECTED_SHA256  /opt/localai/models/model.gguf" | sha256sum -c -
```

**Warning signs:**
- Packer build hangs at "Provisioning with shell script" for >20 minutes then fails
- Partial `.gguf` file in models directory (check file size against expected)
- "Connection reset by peer" in provisioner output

**Phase to address:** Phase 1 (Base Image Build) -- model baking is the longest and most failure-prone step.

**Confidence:** MEDIUM -- based on HuggingFace community reports of download instability and general Packer timeout patterns. Exact failure mode depends on network conditions.

---

### Pitfall 3: LocalAI Default context_size=512 Silently Truncates Conversations

**What goes wrong:**
LocalAI defaults to `context_size: 512` tokens. With chat completions, this limit is consumed by system prompt + conversation history + user message. The model silently truncates input when the context window is exceeded, producing nonsensical or incomplete responses. Users see "the AI stopped working" but there's no error in the API response -- just garbled output.

**Why it happens:**
The 512-token default is a conservative safety value to prevent OOM on small systems. But for coding assistants with system prompts (often 200-500 tokens), this leaves almost no room for actual conversation. GitHub issue #868 documents crashes when context exceeds the configured limit, and issue #7426 (December 2025) reports context_size being ignored in some configurations.

**How to avoid:**
1. ALWAYS set `context_size` explicitly in the model YAML configuration. For a coding assistant with Phi-3-mini (4k native context), set `context_size: 4096`.
2. Calculate memory budget: model file size + KV cache overhead. For Q4_K_M quantization of a 3.8B model at 4096 context, expect ~3 GB model + ~0.5 GB KV cache = ~3.5 GB total.
3. Set the global `--context-size` CLI flag as a fallback, but always prefer per-model YAML.
4. Add a health check that sends a test prompt and validates response coherence.

```yaml
# models/slm-copilot.yaml -- ALWAYS set context_size explicitly
name: slm-copilot
backend: llama-cpp
parameters:
  model: phi-3-mini-4k-instruct-Q4_K_M.gguf
context_size: 4096
threads: 4
mmap: true
mmlock: false
```

**Warning signs:**
- API responses become short, repetitive, or nonsensical after 2-3 conversation turns
- First message works perfectly, subsequent messages degrade
- No errors in LocalAI logs despite broken responses

**Phase to address:** Phase 2 (LocalAI Configuration) -- model YAML must be correct before any API testing.

**Confidence:** HIGH -- verified via official docs (default 512), GitHub issues #868 and #7426, LocalAI FAQ.

---

### Pitfall 4: Nginx Buffering Destroys SSE Streaming for LLM Responses

**What goes wrong:**
Nginx buffers upstream responses by default. When LocalAI streams tokens via Server-Sent Events (SSE) for the OpenAI-compatible `/v1/chat/completions?stream=true` endpoint, Nginx accumulates the entire response in memory before sending anything to the client. The user sees no output for 30-60 seconds (full generation time), then the entire response appears at once. This completely defeats the UX benefit of streaming.

**Why it happens:**
Nginx's `proxy_buffering on` is the default. It's designed for short HTTP responses where buffering improves throughput. But SSE is a long-lived connection where individual events (tokens) must be flushed immediately. Multiple configuration directives interact: `proxy_buffering`, `proxy_cache`, `chunked_transfer_encoding`, `gzip`, and the HTTP version all affect streaming behavior.

**How to avoid:**
Apply ALL of these nginx directives for the streaming endpoint:

```nginx
location /v1/chat/completions {
    proxy_pass http://127.0.0.1:8080;
    proxy_http_version 1.1;
    proxy_set_header Connection '';
    proxy_buffering off;
    proxy_cache off;
    chunked_transfer_encoding off;
    gzip off;
    proxy_read_timeout 300s;
    proxy_send_timeout 300s;
}
```

Additionally, LocalAI should set the `X-Accel-Buffering: no` response header (it may already do this for streaming responses -- verify). Missing any one of these directives can break streaming.

**Warning signs:**
- `curl -N` to the streaming endpoint shows all tokens arriving at once after a long delay
- Client-side `onmessage` events fire in a burst rather than incrementally
- `proxy_buffering` not explicitly set to `off` in nginx config

**Phase to address:** Phase 3 (Nginx Reverse Proxy) -- must be verified with actual streaming test before TLS is layered on top.

**Confidence:** HIGH -- verified via DigitalOcean docs, nginx official docs, multiple community sources all agreeing on the same directives.

---

### Pitfall 5: TLS Chicken-and-Egg -- Nginx Won't Start Without Certificate Files

**What goes wrong:**
If the nginx configuration references `ssl_certificate` and `ssl_certificate_key` files that don't exist yet, nginx refuses to start entirely. This creates a deadlock during first boot: you need nginx running for Let's Encrypt HTTP-01 challenge, but nginx won't start without certificates. Self-signed fallback certs must exist BEFORE nginx starts.

**Why it happens:**
Unlike Apache, nginx validates all referenced file paths at startup. Let's Encrypt's certbot requires a running web server to complete domain validation. If the appliance script tries to set up TLS in a single pass (generate certs, configure nginx, start nginx), the ordering is fragile.

**How to avoid:**
Use a two-phase TLS bootstrap:
1. **Phase A (always):** Generate self-signed certificates during `service_install` (Packer build). Place them at fixed paths that nginx config references.
2. **Phase B (runtime, optional):** During `service_configure`, if Let's Encrypt is requested AND a domain name is provided, run certbot with `--webroot` against the already-running nginx (which is serving with the self-signed cert).
3. After certbot succeeds, `nginx -s reload` to pick up the real certs.

```bash
# During Packer build (service_install):
openssl req -x509 -newkey rsa:2048 -keyout /etc/ssl/private/localai-selfsigned.key \
  -out /etc/ssl/certs/localai-selfsigned.crt -days 3650 -nodes \
  -subj "/CN=localhost"
```

**Warning signs:**
- `systemctl status nginx` shows "nginx: [emerg] cannot load certificate" on first boot
- Appliance reports READY but HTTPS is unreachable
- Let's Encrypt cert acquisition works in testing but fails on first-time appliance deployment

**Phase to address:** Phase 3 (Nginx + TLS) -- the self-signed fallback must be baked into the Packer image.

**Confidence:** HIGH -- well-documented nginx behavior, verified by Let's Encrypt community and multiple deployment guides.

---

### Pitfall 6: service_configure Runs on EVERY Boot -- Non-Idempotent Operations Break on Reboot

**What goes wrong:**
The one-apps framework calls `service_configure` on every VM boot, not just the first boot. If configure contains operations that aren't idempotent (e.g., appending to files without checking, creating duplicate systemd units, re-downloading models, regenerating certificates that clients have already cached), reboots cause duplicate entries, configuration corruption, or unnecessary delays.

**Why it happens:**
The one-apps lifecycle is: `install` (Packer time, once) -> `configure` (every boot) -> `bootstrap` (every boot after configure). This is by design for reconfigurability (`ONE_SERVICE_RECONFIGURABLE=true`), but developers often write configure scripts assuming single execution.

**How to avoid:**
1. Every operation in `service_configure` must be idempotent. Use `>` (overwrite) not `>>` (append). Use `mkdir -p` not `mkdir`. Use `cat > file` not `echo >> file`.
2. For TLS certificates: only regenerate if the IP/hostname changed or certs don't exist. Check `openssl x509 -in cert.pem -noout -subject` against current hostname.
3. For model YAML: always overwrite entirely, never patch.
4. For systemd units: always overwrite + `systemctl daemon-reload`.
5. Test by: deploy VM, configure, reboot, verify everything still works identically.

**Warning signs:**
- Duplicate entries in config files after reboot
- Systemd unit shows "changed on disk" warnings
- Services fail to start on second boot but worked on first
- TLS certificate SAN doesn't match after IP change

**Phase to address:** Phase 2 and beyond -- every lifecycle script must be tested with reboot cycles.

**Confidence:** HIGH -- verified from author's direct experience with Flower FL appliance (documented in project memory), corroborated by one-apps documentation and GitHub issues.

---

### Pitfall 7: CPU Instruction Set Mismatch -- LocalAI Binary Crashes with SIGILL

**What goes wrong:**
LocalAI (and its embedded llama.cpp) uses AVX/AVX2/AVX-512 SIMD instructions for performance. If the binary is compiled for AVX2 but runs on a CPU that only supports AVX (or neither), the process crashes with SIGILL (illegal instruction). In a VM, this depends on the QEMU CPU model: `host` passthrough exposes real CPU features, but `qemu64`/`kvm64` models expose minimal instruction sets.

**Why it happens:**
- Packer builds with `-cpu host` expose the build host's AVX2 support
- Production VMs may use different QEMU CPU models (especially in multi-host clusters)
- OpenNebula template `CPU_MODEL` defaults vary by deployment
- LocalAI v3.10.0 (January 2026) included specific crash fixes for AVX-only CPUs, confirming this is a real and recent issue

**How to avoid:**
1. Download the "fallback" or "noavx" LocalAI binary variant that uses no SIMD optimizations (slower but universally compatible).
2. OR: document in appliance requirements that the VM must be deployed with `CPU_MODEL="host"` or a model supporting AVX2.
3. Add a runtime check in `service_configure` that verifies AVX support before starting LocalAI:

```bash
if ! grep -q avx2 /proc/cpuinfo; then
    msg warning "CPU does not support AVX2 -- inference will be slower"
    # Optionally switch to noavx binary variant
fi
```

**Warning signs:**
- LocalAI process exits immediately with signal 4 (SIGILL)
- `journalctl -u localai` shows no log output (crash before any logging)
- Works in Packer build but fails when deployed to different hardware

**Phase to address:** Phase 1 (Base Image Build) -- binary selection must account for target CPU diversity.

**Confidence:** HIGH -- verified via LocalAI GitHub issue #6348, #3367, release notes for v3.10.0 mentioning AVX crash fixes.

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Hardcode single model in image | Simpler build, no YAML complexity | Users can't swap models without rebuilding image | Never -- always support model override via context var |
| Skip mmap, load full model to RAM | Simpler memory model | Wastes RAM on systems with limited memory; prevents running alongside other services | Only if VM is dedicated single-model server |
| Use `proxy_buffering off` globally | Fixes streaming | Degrades performance for non-streaming endpoints (health checks, model list) | Never -- scope buffering off to streaming endpoints only |
| Self-signed cert only, no Let's Encrypt path | Simpler TLS setup | Every client must disable cert verification; breaks IDE integrations that expect valid certs | MVP only -- add Let's Encrypt in Phase 3+ |
| Pin LocalAI to exact version, never update | Stability | Miss security patches, bug fixes (e.g., AVX crash fixes in v3.10.0) | Acceptable for marketplace release; provide upgrade path |
| Download model at runtime instead of baking | Smaller image, user choice | 30-60 min first-boot delay; network dependency; can fail silently | Never for primary model; acceptable for user-added models |

## Integration Gotchas

Common mistakes when connecting components in this appliance.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Nginx -> LocalAI | `proxy_pass http://localhost:8080` with nginx starting before LocalAI is ready | Use systemd `After=localai.service` + health check loop in bootstrap waiting for `/readyz` |
| LocalAI model YAML | Setting `backend: llama` instead of `backend: llama-cpp` | Always use `llama-cpp` for GGUF models. `llama` is deprecated/non-existent in current versions |
| LocalAI chat template | Omitting `template.chat_message` field, expecting auto-detection | Auto-detection works for gallery models but fails for manual GGUF files. Always specify chat template explicitly in YAML |
| OpenNebula context -> LocalAI env | Passing ONEAPP_ vars directly as LocalAI env vars | Map ONEAPP_ vars to LocalAI's expected env var names in configure script. LocalAI uses `LOCALAI_` prefix or CLI flags |
| systemd service -> LocalAI | Using `Type=simple` without readiness check | Use `Type=notify` if supported, or `Type=simple` with `ExecStartPost` health check. LocalAI's `/readyz` endpoint returns 200 only when models are loaded |
| HuggingFace download -> Packer | Direct `curl` without resume support | Use `wget -c` or `huggingface-cli download` with retry logic |
| QCOW2 image -> OpenNebula | Uploading uncompressed 60 GB QCOW2 | Run `qemu-img convert -O qcow2 -c` post-build to compress. Also `fstrim -a` inside VM before image capture |

## Performance Traps

Patterns that work in testing but fail in production.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Default context_size=512 | Works for "hello world" tests, breaks for real conversations | Set context_size to model's trained max (e.g., 4096) in YAML | >2 conversation turns with system prompt |
| threads = ALL cores | Good single-user perf, terrible multi-user | Set threads to (physical_cores - 1) or (physical_cores / 2) for headroom | >2 concurrent requests |
| No model preloading | First request takes 15-60s to load model from disk | Use PRELOAD_MODELS env var or `--preload-models` CLI flag | First user request after boot/restart |
| mmap without sufficient page cache | Model loads fast initially | When OS reclaims page cache under memory pressure, inference stutters with disk I/O | VM memory < 2x model file size |
| proxy_read_timeout=60s (nginx default) | Works for fast queries | Long generation (2000+ tokens on CPU) can take >60s; nginx kills the connection mid-stream | Complex code generation requests |
| Single LocalAI process, no queuing | Works with 1 user | Second concurrent request blocks until first completes; third may timeout | >1 simultaneous user |

## Security Mistakes

Domain-specific security issues beyond general web security.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Exposing LocalAI port 8080 directly without API key | Anyone on the network can use the LLM, run arbitrary prompts, load models | Set `API_KEY` env var; only expose via nginx with auth |
| Serving LocalAI WebUI on the same port as API | Admin interface (model install, config changes) accessible to API consumers | Disable WebUI (`--no-webui`) or bind to localhost-only; expose only API via nginx |
| Model YAML with `external_grpc` or `external` backend | Allows arbitrary process execution on the host | Never use external backends in a marketplace appliance; validate YAML contents |
| Self-signed cert with weak key (1024-bit RSA) | Easily brute-forced | Use 2048-bit RSA minimum, prefer 4096-bit; use ECDSA P-256 for performance |
| Let's Encrypt with wildcard domain or bare IP | Cert acquisition fails silently; falls back to self-signed without notification | Validate domain resolves to VM IP before attempting certbot; log clear warnings |
| OneGate token accessible to LocalAI process | LLM could be prompted to extract OneGate token via prompt injection | Run LocalAI as unprivileged user; restrict OneGate token file permissions to root only |
| Storing API keys in ONEAPP_ context vars (visible in Sunstone) | Anyone with Sunstone read access sees the API key | Document that API keys in context vars are not secrets; provide alternative key management |

## UX Pitfalls

Common user experience mistakes in this domain.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| First request after boot takes 60s (model loading) | User thinks appliance is broken | Preload model at boot; add health check that confirms model is loaded; report READY only after `/readyz` returns 200 |
| No feedback during model loading | User hits API, gets timeout/error | Return HTTP 503 with `Retry-After` header and message "Model loading, please wait" |
| Default model is 14 GB download | Users with limited bandwidth wait hours on first deploy | Bake the default model into the QCOW2 image during Packer build |
| Error messages reference LocalAI internals | "rpc error: code = Unavailable desc = error reading from server: EOF" is meaningless to users | Wrap LocalAI errors in user-friendly messages at the nginx layer |
| Streaming endpoint requires specific client configuration | User's HTTP client doesn't handle SSE properly | Provide non-streaming endpoint as default; document streaming as opt-in |
| Context variable names are opaque | `ONEAPP_SLM_CONTEXT_SIZE` means nothing to non-experts | Use clear descriptions in ONE_SERVICE_PARAMS and provide a README with examples |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **LocalAI responds to /v1/chat/completions:** Often missing chat template in model YAML -- verify response format matches OpenAI spec (check `choices[0].message.content` is populated, not empty)
- [ ] **Nginx TLS works:** Often missing intermediate CA chain -- verify with `openssl s_client -connect host:443 -showcerts` shows full chain
- [ ] **Streaming works through nginx:** Often only tested with curl, not through TLS -- verify SSE streaming works through HTTPS, not just HTTP
- [ ] **Model is loaded:** Often LocalAI starts but model isn't preloaded -- verify `/readyz` returns 200 AND `/v1/models` lists the expected model
- [ ] **Appliance survives reboot:** Often works on first boot but breaks on second -- test full stop/start cycle, verify all services come up
- [ ] **Context variables actually take effect:** Often YAML is generated but LocalAI isn't restarted -- verify `systemctl restart localai` happens after config regeneration
- [ ] **QCOW2 image is compressed:** Often 60 GB raw image uploaded to marketplace -- verify `qemu-img info` shows actual size << virtual size
- [ ] **CPU compatibility:** Often only tested on build host's CPU -- verify with `qemu-system-x86_64 -cpu qemu64` (minimal feature set)
- [ ] **Disk space sufficient:** Often model fills disk during Packer build -- verify `df -h` shows >5 GB free after model download in the VM

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Install script broken | LOW | Download binary directly from GitHub releases; no reinstall needed |
| Model download fails in Packer | MEDIUM | Re-run Packer build (30-60 min); consider pre-staging model on build host |
| Context truncation | LOW | Update model YAML `context_size`, restart LocalAI; no rebuild needed |
| Nginx buffering breaks streaming | LOW | Add 6 nginx directives, `nginx -s reload`; no rebuild needed |
| TLS chicken-and-egg | LOW | Generate self-signed cert manually, restart nginx; automate in next build |
| Non-idempotent configure | MEDIUM | Fix script, rebuild image OR SSH in and fix config manually |
| SIGILL crash on wrong CPU | MEDIUM | Replace binary with noavx variant via SSH; long-term fix requires rebuild with correct binary |
| 60 GB uncompressed image in marketplace | HIGH | Must rebuild and re-upload; `qemu-img convert -c` on existing image as workaround |

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Broken install script | Phase 1: Base Image | `local-ai --version` succeeds; `/readyz` returns 200 |
| Model download timeout | Phase 1: Base Image | SHA256 checksum of baked model matches expected value |
| context_size=512 default | Phase 2: Model Config | Send 3-turn conversation via API; verify coherent response |
| Nginx buffering kills SSE | Phase 3: Nginx Proxy | `curl -N` shows incremental token delivery |
| TLS chicken-and-egg | Phase 3: Nginx + TLS | `nginx -t` passes on fresh boot; HTTPS responds |
| Non-idempotent configure | Phase 2+ (all scripts) | Deploy, reboot, verify all services still work |
| CPU SIGILL crash | Phase 1: Base Image | Test with `qemu-system -cpu qemu64` during CI |
| Model not preloaded | Phase 2: Model Config | `/v1/models` returns model within 5s of READY status |
| proxy_read_timeout too short | Phase 3: Nginx Proxy | Generate 2000-token response; verify no nginx timeout |
| QCOW2 image bloat | Phase 1: Base Image | `qemu-img info` actual size < 25 GB for 60 GB virtual |
| API exposed without auth | Phase 3: Nginx Proxy | `curl` without API key returns 401 |
| Watchdog kills long inference | Phase 2: Model Config | Set WATCHDOG_BUSY_TIMEOUT > max expected generation time |

## Sources

- [LocalAI install.sh issue #8032](https://github.com/mudler/LocalAI/issues/8032) -- install script broken, HIGH confidence
- [LocalAI Model Configuration](https://localai.io/advanced/model-configuration/) -- YAML schema, context_size default 512, HIGH confidence
- [LocalAI Runtime Settings](https://localai.io/features/runtime-settings/) -- WATCHDOG, PRELOAD, threads, HIGH confidence
- [LocalAI context crash issue #868](https://github.com/mudler/LocalAI/issues/868) -- context exceeding configured limit causes crash
- [LocalAI context_size ignored issue #7426](https://github.com/mudler/LocalAI/issues/7426) -- December 2025, context_size bug
- [LocalAI AVX2 requirement issue #6348](https://github.com/mudler/LocalAI/issues/6348) -- SIGILL on older CPUs
- [LocalAI v3.10.0 release notes](https://github.com/mudler/LocalAI/releases) -- AVX-only crash fixes, January 2026
- [LocalAI VRAM/Memory Management](https://localai.io/advanced/vram-management/) -- watchdog idle/busy configuration
- [HuggingFace download instability](https://discuss.huggingface.co/t/download-instability-disconnects/137529) -- CDN issues with large files
- [Nginx SSE buffering fix](https://www.digitalocean.com/community/questions/nginx-optimization-for-server-sent-events-sse) -- DigitalOcean community, HIGH confidence
- [Nginx SSE configuration](https://objectgraph.com/blog/optimizing-sse-nginx-streaming/) -- comprehensive proxy directives for SSE
- [SSE troubleshooting in multi-service architecture](https://medium.com/@wang645788/troubleshooting-server-sent-events-sse-in-a-multi-service-architecture-5084ce155ea0) -- proxy_http_version 1.1 requirement
- [Let's Encrypt chicken-and-egg](https://medium.com/@arthur.lewis/solving-the-chicken-and-egg-problem-setting-up-a-lets-encrypt-ssl-certificate-for-nginx-c1a194f881bd) -- self-signed bootstrap pattern
- [Packer QEMU builder docs](https://developer.hashicorp.com/packer/integrations/hashicorp/qemu/latest/components/builder/qemu) -- skip_compaction, disk_compression
- [QCOW2 shrinking with qemu-img convert](https://pve.proxmox.com/wiki/Shrink_Qcow2_Disk_Files) -- compression reduces 50 GB to 25 GB
- [OpenNebula one-apps](https://github.com/OpenNebula/one-apps/) -- appliance lifecycle (install/configure/bootstrap)
- [llama.cpp CPU inference guide](https://www.rogerngo.com/blog/llamacpp-build-guide-for-cpu-inferencing) -- thread count, mmap behavior
- [llama.cpp memory discussion #10068](https://github.com/ggml-org/llama.cpp/discussions/10068) -- KV cache memory calculation
- Author's direct experience with Flower FL OpenNebula appliance (documented in project memory)

---
*Pitfalls research for: CPU-only LLM inference appliance (OpenNebula marketplace)*
*Researched: 2026-02-13*
