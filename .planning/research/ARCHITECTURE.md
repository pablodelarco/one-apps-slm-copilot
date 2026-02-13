# Architecture Patterns

**Domain:** CPU-only LLM inference appliance (OpenNebula marketplace)
**Researched:** 2026-02-13

## Recommended Architecture

### System Overview

Single-VM appliance with three runtime components managed by systemd, built by Packer into a self-contained QCOW2 image. All components run on the same machine -- no containers, no orchestration.

```
                         INTERNET / CORPORATE NETWORK
                                    |
                                    | HTTPS :443 (TLS + Basic Auth)
                                    v
                        +-----------------------+
                        |   Nginx Reverse Proxy |
                        |   (systemd: nginx)    |
                        |                       |
                        |  - TLS termination    |
                        |  - Basic auth         |
                        |  - CORS headers       |
                        |  - SSE streaming      |
                        |  - Rate limiting      |
                        +-----------+-----------+
                                    |
                                    | HTTP localhost:8080 (plaintext, loopback only)
                                    v
                        +-----------------------+
                        |   LocalAI Engine      |
                        |   (systemd: local-ai) |
                        |                       |
                        |  - OpenAI-compatible  |
                        |  - llama-cpp backend  |
                        |  - Model config YAML  |
                        |  - Auto-downloads     |
                        |    backend on start   |
                        +-----------+-----------+
                                    |
                                    | mmap() file I/O
                                    v
                        +-----------------------+
                        |   Devstral Small 2    |
                        |   (GGUF on disk)      |
                        |                       |
                        |  - 24B Q4_K_M ~14 GB  |
                        |  - /opt/local-ai/     |
                        |    models/            |
                        +-----------------------+

DEVELOPER WORKSTATION
  VS Code + Cline extension
      |
      +-- "OpenAI Compatible" provider
      +-- Base URL: https://<vm-ip>/v1
      +-- API Key: from ONEAPP_* context var
      +-- Model ID: devstral-small-2
```

### Component Boundaries

| Component | Responsibility | Listens On | Communicates With |
|-----------|---------------|------------|-------------------|
| **Nginx** | TLS termination, basic auth, CORS, SSE proxy, rate limiting | 0.0.0.0:443, 0.0.0.0:80 (redirect) | LocalAI (localhost:8080) |
| **LocalAI** | OpenAI-compatible API, llama-cpp inference orchestration, model management | 127.0.0.1:8080 | GGUF model file (disk I/O) |
| **GGUF model** | Passive data file, memory-mapped by llama-cpp | N/A (file on disk) | Read by LocalAI |
| **Appliance script** | Lifecycle management (install/configure/bootstrap) | N/A (runs at boot) | All components |
| **one-context** | OpenNebula contextualization (networking, SSH, ONEAPP_* vars) | N/A (runs at boot) | Appliance script (via env vars) |

### Data Flow

**Request path (inference):**
1. Cline sends HTTPS POST to `https://<vm-ip>/v1/chat/completions` with Bearer token
2. Nginx validates TLS, checks basic auth credentials, adds CORS headers
3. Nginx proxies to `http://127.0.0.1:8080/v1/chat/completions` with buffering disabled
4. LocalAI receives request, routes to llama-cpp backend for model `devstral-small-2`
5. llama-cpp loads model weights via mmap (already in page cache after first load)
6. llama-cpp generates tokens, streams back as SSE `data:` chunks
7. LocalAI streams SSE response to Nginx
8. Nginx forwards SSE stream to Cline (proxy_buffering off)
9. Cline renders tokens in real-time

**Streaming SSE detail:** The OpenAI-compatible API uses `stream: true` in the request body. Response is `Content-Type: text/event-stream` with `data: {"choices":[{"delta":{"content":"token"}}]}` lines. Nginx must NOT buffer these -- requires `proxy_buffering off`, `proxy_http_version 1.1`, and `X-Accel-Buffering: no`.

**Configuration path (boot-time):**
1. OpenNebula injects ONEAPP_* variables via one-context CD-ROM
2. one-context runs `/etc/one-appliance/service` which sources the appliance script
3. `service_configure()` reads ONEAPP_* vars, generates Nginx config, LocalAI model YAML, TLS certs
4. `service_bootstrap()` starts systemd services, runs health checks, writes report file

## Component Detail

### LocalAI (Inference Engine)

**Confidence:** HIGH (official docs verified)

**Installation:** Pre-built binary from GitHub releases. Single file `local-ai` placed at `/opt/local-ai/bin/local-ai`. The install script (install.sh) is broken per issue #8032 -- use direct binary download.

**Binary:** `https://github.com/mudler/LocalAI/releases/download/v3.11.0/local-ai-Linux-x86_64`

**Key architecture decisions:**
- Bind to `127.0.0.1:8080` (loopback only) -- never exposed to network
- `--threads` set to physical core count (ONEAPP_LOCALAI_THREADS or auto-detect via `nproc`)
- `--context-size` set to model's window (128K for Devstral, but constrained by RAM)
- `--single-active-backend` deprecated; use `--max-active-backends=1` (single model appliance)
- `--watchdog-idle=true` with `--watchdog-idle-timeout=30m` to release memory when idle
- `--disable-webui=true` (API-only, Cline is the interface)
- `--cors=false` (Nginx handles CORS)
- `--api-keys` NOT used (Nginx handles auth -- avoids CORS+API key bug #4576)
- `--log-level` configurable via ONEAPP_LOCALAI_LOG_LEVEL

**v3.x architecture note:** Since mid-2025, backends are external to the main binary. LocalAI auto-downloads the required backend (llama-cpp) on first model load. This means the binary itself is small (~50 MB) but first inference request triggers a backend download (~200 MB). For an appliance, pre-warm this during Packer build by running a test inference.

**Model configuration YAML:** Placed at `/opt/local-ai/models/devstral-small-2.yaml`:

```yaml
name: devstral-small-2
backend: llama-cpp
parameters:
  model: devstral-small-2-q4km.gguf
  temperature: 0.2
  top_p: 0.95
context_size: 32768
threads: 16
mmap: true
mmlock: false
```

**Systemd unit:** `/etc/systemd/system/local-ai.service`

```ini
[Unit]
Description=LocalAI Inference Engine
After=network.target

[Service]
Type=simple
User=localai
Group=localai
ExecStart=/opt/local-ai/bin/local-ai run \
    --address 127.0.0.1:8080 \
    --models-path /opt/local-ai/models \
    --threads ${THREADS} \
    --max-active-backends 1 \
    --watchdog-idle \
    --watchdog-idle-timeout 30m \
    --disable-webui \
    --log-level ${LOG_LEVEL}
Restart=on-failure
RestartSec=10
TimeoutStartSec=300
LimitNOFILE=65536
Environment=LOCALAI_THREADS=16
Environment=LOCALAI_LOG_LEVEL=info

[Install]
WantedBy=multi-user.target
```

### Nginx (Reverse Proxy)

**Confidence:** HIGH (well-established patterns)

**Role:** External-facing gateway. Handles all security concerns that LocalAI does not: TLS, authentication, CORS, rate limiting.

**Key configuration patterns:**

```nginx
# /etc/nginx/sites-available/localai-proxy
upstream localai {
    server 127.0.0.1:8080;
    keepalive 4;
}

server {
    listen 443 ssl http2;
    server_name _;

    ssl_certificate     /etc/nginx/ssl/server.crt;
    ssl_certificate_key /etc/nginx/ssl/server.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    # Basic auth
    auth_basic           "SLM-Copilot";
    auth_basic_user_file /etc/nginx/.htpasswd;

    # CORS headers (Cline needs these)
    add_header Access-Control-Allow-Origin  "*" always;
    add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Authorization, Content-Type" always;

    # Handle preflight
    if ($request_method = OPTIONS) {
        return 204;
    }

    # Proxy to LocalAI -- SSE streaming support
    location /v1/ {
        proxy_pass http://localai/v1/;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;

        # Critical for SSE streaming
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
        add_header X-Accel-Buffering no always;

        # Large request bodies (code context)
        client_max_body_size 10m;
    }

    # Health endpoint (no auth)
    location /health {
        auth_basic off;
        proxy_pass http://localai/readyz;
    }
}

server {
    listen 80;
    server_name _;
    return 301 https://$host$request_uri;
}
```

**TLS strategy (two modes):**
1. **Self-signed (default):** Generated at first boot by `service_bootstrap()`. Works immediately, Cline accepts with "allow insecure" setting. Good for demos and internal networks.
2. **Let's Encrypt (optional):** If ONEAPP_LETSENCRYPT_DOMAIN is set, run `certbot --nginx -d $domain --non-interactive --agree-tos`. Requires public DNS + port 80 reachable. Certbot auto-installs renewal cron.

**Timeout rationale:** `proxy_read_timeout 600s` (10 minutes) because CPU inference on a 24B model can take 60-120 seconds for long completions. Default 60s will cause premature disconnects.

### Model File (GGUF)

**Confidence:** HIGH (HuggingFace verified)

**Source:** `bartowski/mistralai_Devstral-Small-2-24B-Instruct-2512-GGUF` on HuggingFace
**Quantization:** Q4_K_M -- best balance of quality vs size for CPU inference
**File size:** ~14 GB
**Runtime RAM:** ~14 GB (mmap + resident working set)
**Context window:** 128K tokens native, but context_size should be set conservatively (32K-65K) to control RAM usage. Each 1K context tokens costs ~2 MB RAM for KV cache at Q4 precision.

**Baked into image:** Downloaded during Packer build, NOT at runtime. This is critical for:
- Instant deployment (no 14 GB download on first boot)
- Air-gapped environments (no internet required)
- Predictable image size
- Consistent model version across all deployments

### Appliance Script (Lifecycle)

**Confidence:** HIGH (proven pattern from Flower appliance)

Following the one-apps three-stage lifecycle, exactly as implemented in the Flower SuperLink/SuperNode appliances:

**Stage 1: `service_install()`** -- Runs during Packer build (once)
- Install Nginx from Ubuntu repos
- Download LocalAI binary from GitHub releases
- Download GGUF model from HuggingFace
- Create directory structure (/opt/local-ai/models, /opt/local-ai/bin, etc.)
- Pre-warm: run a test inference to trigger backend download and verify model loads
- Create `localai` system user (UID/GID for least-privilege)
- Install certbot (for optional Let's Encrypt)
- Stop services (layers persist on disk)

**Stage 2: `service_configure()`** -- Runs every boot
- Read ONEAPP_* context variables with defaults
- Validate all configuration values (fail-fast)
- Generate LocalAI model YAML from ONEAPP_* vars (context_size, threads, temperature)
- Generate LocalAI systemd environment file
- Generate Nginx site config from ONEAPP_* vars (auth credentials, TLS mode, CORS)
- Generate /etc/nginx/.htpasswd from ONEAPP_COPILOT_PASSWORD
- Handle TLS certificates (self-signed generation or operator-provided decode)
- Write systemd unit files for both services

**Stage 3: `service_bootstrap()`** -- Runs after configure, starts services
- Start LocalAI systemd service
- Wait for LocalAI health check (GET /readyz on localhost:8080)
- Start Nginx systemd service
- Wait for Nginx to accept connections on 443
- Optionally run certbot for Let's Encrypt
- Write report file to /etc/one-appliance/config
- Report includes: endpoint URL, credentials, model info, status

### Build Pipeline (Packer)

**Confidence:** HIGH (proven pattern from Flower appliance)

```
Ubuntu 24.04 cloud image (QCOW2, ~3.5 GB)
    |
    v
Packer QEMU builder (KVM accelerated)
    |
    +-- cloud-init seed ISO (SSH access for provisioning)
    |
    +-- Step 1: SSH hardening
    +-- Step 2: Install one-context package
    +-- Step 3: Create one-appliance directory structure
    +-- Step 4: Install one-apps framework files
    +-- Step 5: Install appliance script
    +-- Step 6: Configure context hooks
    +-- Step 7: Run service_install()
    |       +-- Install Nginx (~5 MB)
    |       +-- Download LocalAI binary (~50 MB)
    |       +-- Download GGUF model (~14 GB)  <-- SLOW, ~10 min on fast link
    |       +-- Pre-warm backend download (~200 MB)
    |       +-- Test inference (validates everything works)
    |
    +-- Step 8: Cleanup (cloud-init, apt cache, machine-id)
    |
    v
Raw QCOW2 (~20-25 GB)
    |
    v
qemu-img convert -c -O qcow2 (compress)
    |
    v
Compressed QCOW2 (~10-15 GB) -> Marketplace upload
```

**Packer VM resources:** 4 vCPU, 16 GB RAM, 50 GB disk. The model download and test inference need RAM to verify, but the build itself is I/O-bound.

**Critical build consideration:** The 14 GB model download dominates build time. Mirror the GGUF file locally or use HuggingFace CDN. Build host needs ~50 GB free disk (base image + model + output + temp).

## Patterns to Follow

### Pattern 1: Loopback-Only Backend

**What:** Bind inference engine to 127.0.0.1, never to 0.0.0.0. All external access goes through Nginx.

**When:** Always. This is a security pattern.

**Why:** LocalAI has no TLS (closed as "not planned" #1295) and the CORS+API key interaction is buggy (#4576). Nginx handles all external-facing concerns. The loopback binding means even if Nginx misconfiguration occurs, LocalAI is not directly reachable.

### Pattern 2: SSE-Aware Proxy Configuration

**What:** Disable all buffering in the Nginx proxy path for LLM streaming responses.

**When:** Any time you proxy an LLM inference endpoint that supports streaming.

**Why:** Nginx buffers responses by default. For SSE streaming (token-by-token generation), buffering destroys the user experience -- tokens batch up and arrive in bursts instead of streaming smoothly. The combination of `proxy_buffering off`, `proxy_http_version 1.1`, `X-Accel-Buffering: no`, and generous timeouts (600s) is required.

### Pattern 3: Model Baked Into Image

**What:** Download the GGUF model during Packer build, not at runtime.

**When:** When model size is large (>1 GB) and the target is a marketplace appliance.

**Why:** A 14 GB download at first boot takes 10+ minutes even on fast connections, fails in air-gapped environments, and creates inconsistent deployment experiences. Baking the model in makes deployment instant and predictable.

### Pattern 4: Backend Pre-Warming

**What:** During Packer build, after installing LocalAI and the model, start LocalAI temporarily and run a test inference request. This triggers the llama-cpp backend download and verifies the model loads correctly.

**When:** Always for appliance builds since LocalAI v3.x auto-downloads backends.

**Why:** Without pre-warming, the first inference request after deployment triggers a ~200 MB backend download, adding unexpected latency. Pre-warming also serves as a build-time validation that the model file is not corrupt and the binary works.

```bash
# In service_install(), after downloading model:
/opt/local-ai/bin/local-ai run --address 127.0.0.1:8080 \
    --models-path /opt/local-ai/models --threads 2 &
LOCALAI_PID=$!
# Wait for readiness
for i in $(seq 1 120); do
    curl -s http://127.0.0.1:8080/readyz && break
    sleep 2
done
# Test inference (triggers backend download + model load)
curl -s http://127.0.0.1:8080/v1/chat/completions \
    -d '{"model":"devstral-small-2","messages":[{"role":"user","content":"hi"}],"max_tokens":5}'
# Shutdown
kill $LOCALAI_PID
wait $LOCALAI_PID 2>/dev/null
```

### Pattern 5: Three-Stage Appliance Lifecycle

**What:** Separate install (build-time), configure (every boot), bootstrap (first boot + service start) into distinct functions.

**When:** All OpenNebula marketplace appliances.

**Why:** This is the one-apps framework convention. Install runs in Packer (no network context, no ONEAPP_* vars). Configure runs at every boot (idempotent, reads context vars, generates config files). Bootstrap starts services and does health checks.

**Key distinction:** `service_configure` must be idempotent -- it regenerates all config files from ONEAPP_* vars on every boot, supporting reconfiguration without rebuild.

## Anti-Patterns to Avoid

### Anti-Pattern 1: Exposing LocalAI Directly to Network

**What:** Binding LocalAI to 0.0.0.0 and relying on its built-in --api-keys for auth.

**Why bad:** No TLS support (issue #1295 closed as "not planned"). CORS + API key bug (#4576) breaks browser-based clients. No rate limiting, no request logging, no connection limits.

**Instead:** Always bind to 127.0.0.1. Use Nginx for all external-facing concerns.

### Anti-Pattern 2: Runtime Model Download

**What:** Downloading the GGUF model at first boot from HuggingFace.

**Why bad:** 14 GB download takes 10+ minutes, fails in air-gapped zones, subject to CDN rate limits, creates non-deterministic deployment. If HuggingFace is down, the appliance is broken.

**Instead:** Bake the model into the QCOW2 image during Packer build.

### Anti-Pattern 3: Docker for Single-Binary Services

**What:** Running LocalAI or Nginx in Docker containers.

**Why bad:** Adds ~500 MB to image size (Docker CE), adds boot-time dependency (Docker daemon), adds operational complexity (container networking, volume mounts), and provides zero benefit for single-binary services that run natively on the host.

**Instead:** Direct binary installation + systemd for process management. This is explicitly stated in the project constraints.

### Anti-Pattern 4: Unbounded Context Size

**What:** Setting context_size to the model's maximum (128K tokens) without considering RAM.

**Why bad:** KV cache for 128K context at Q4 precision costs ~4-8 GB additional RAM beyond the model weights. On a 32 GB VM, model (14 GB) + OS (2 GB) + KV cache (8 GB) + overhead = 24+ GB, leaving no headroom.

**Instead:** Default to 32K context_size. Allow override via ONEAPP_LOCALAI_CONTEXT_SIZE with validation that warns if total estimated RAM exceeds available.

### Anti-Pattern 5: Synchronous Health Checks with Short Timeouts

**What:** Using default 60s proxy_read_timeout for LLM inference requests.

**Why bad:** CPU inference on a 24B model routinely takes 30-120 seconds for long completions. A 60s timeout causes frequent 504 Gateway Timeout errors that are invisible to the user (Cline just shows "request failed").

**Instead:** Set `proxy_read_timeout 600s` (10 minutes). CPU inference is slow but reliable -- let it finish.

## Directory Structure

```
/opt/local-ai/
  bin/
    local-ai                          # Pre-built binary (~50 MB)
  models/
    devstral-small-2.yaml             # Model config (generated by configure)
    devstral-small-2-q4km.gguf        # GGUF weights (~14 GB, baked in)
  backends/                           # Auto-downloaded by LocalAI on first load
    llama-cpp-grpc/                   # llama-cpp backend binary
  config/
    local-ai.env                      # Environment file for systemd

/etc/nginx/
  sites-available/
    localai-proxy                     # Generated by configure
  sites-enabled/
    localai-proxy -> ../sites-available/localai-proxy
  ssl/
    server.crt                        # Self-signed or Let's Encrypt
    server.key
  .htpasswd                           # Basic auth credentials

/etc/systemd/system/
  local-ai.service                    # Generated by configure
  # nginx.service -- installed by apt (already exists)

/etc/one-appliance/
  service                             # one-apps framework entry point
  service.d/
    appliance.sh                      # Our appliance lifecycle script
  lib/
    common.sh                         # one-apps common functions
    functions.sh                      # one-apps helper functions
  config                              # Report file (written by bootstrap)

/var/log/one-appliance/               # Appliance logs
```

## Scalability Considerations

| Concern | Demo (1 user) | Team (5 users) | Department (20+ users) |
|---------|---------------|-----------------|----------------------|
| Concurrent requests | 1 at a time (serial inference) | Queue in LocalAI, 1 active | Need multiple VMs behind load balancer |
| RAM | 32 GB (14 GB model + 18 GB headroom) | 32 GB (same, sequential) | 32 GB per VM instance |
| CPU | 16 vCPU (all threads to inference) | 16 vCPU (contention visible) | 32 vCPU per VM for responsiveness |
| Response time | 30-120s per completion | 30-120s + queue wait | Scale horizontally, not vertically |
| Context window | 32K default | 32K default | Reduce to 16K if RAM-constrained |

**Scaling strategy:** This is a single-VM appliance. For multi-user scenarios, deploy multiple instances behind an OpenNebula load balancer or use OneFlow to manage a pool. The appliance itself does not need to scale internally -- CPU inference is inherently serial per request.

## Build Order (Dependencies)

The components have a clear dependency chain that dictates implementation order:

```
1. Appliance script skeleton (service_install/configure/bootstrap stubs)
   |
   +---> 2. LocalAI installation + model download (in service_install)
   |         |
   |         +---> 3. Model YAML configuration (in service_configure)
   |         |
   |         +---> 4. LocalAI systemd service (in service_configure)
   |         |
   |         +---> 5. Backend pre-warming (in service_install, after model)
   |
   +---> 6. Nginx installation (in service_install)
   |         |
   |         +---> 7. TLS certificate generation (in service_bootstrap)
   |         |
   |         +---> 8. Nginx proxy config (in service_configure)
   |         |
   |         +---> 9. Basic auth setup (in service_configure)
   |
   +---> 10. Health checks + report file (in service_bootstrap)
   |
   +---> 11. Packer build definition
   |
   +---> 12. Marketplace metadata (YAML)
```

**Critical path:** Items 1-5 (LocalAI + model) are the foundation. Nothing else works without a functioning inference engine. Nginx (6-9) depends on having LocalAI running to proxy to. The Packer build (11) wraps everything.

**Recommended phase structure based on architecture:**
1. **Phase 1:** Appliance script + LocalAI + model (items 1-5) -- get inference working
2. **Phase 2:** Nginx proxy + TLS + auth (items 6-9) -- secure the endpoint
3. **Phase 3:** Packer build + marketplace metadata (items 11-12) -- package for deployment
4. **Phase 4:** Testing + documentation -- validate end-to-end

## Sources

- [LocalAI official documentation](https://localai.io/) - HIGH confidence
- [LocalAI CLI reference](https://localai.io/reference/cli-reference/) - HIGH confidence
- [LocalAI model configuration](https://localai.io/advanced/model-configuration/) - HIGH confidence
- [LocalAI GitHub releases (v3.11.0)](https://github.com/mudler/LocalAI/releases) - HIGH confidence
- [LocalAI TLS issue #1295](https://github.com/mudler/LocalAI/issues/1295) - HIGH confidence
- [LocalAI CORS+API key bug #4576](https://github.com/mudler/LocalAI/issues/4576) - HIGH confidence
- [LocalAI install script bug #8032](https://github.com/mudler/LocalAI/issues/8032) - HIGH confidence
- [NGINX AI proxy blog post](https://blog.nginx.org/blog/using-nginx-as-an-ai-proxy) - HIGH confidence
- [Cline OpenAI Compatible provider docs](https://docs.cline.bot/provider-config/openai-compatible) - HIGH confidence
- [bartowski Devstral GGUF on HuggingFace](https://huggingface.co/bartowski/mistralai_Devstral-Small-2-24B-Instruct-2512-GGUF) - HIGH confidence
- [OpenNebula one-apps GitHub](https://github.com/OpenNebula/one-apps/) - HIGH confidence
- [Packer QEMU builder docs](https://developer.hashicorp.com/packer/integrations/hashicorp/qemu/latest/components/builder/qemu) - HIGH confidence
- Flower-OpenNebula appliance scripts (local codebase) - HIGH confidence (direct examination)
