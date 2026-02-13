# Stack Research: SLM-Copilot

**Domain:** CPU-only AI coding assistant (OpenNebula marketplace appliance)
**Researched:** 2026-02-13
**Confidence:** MEDIUM-HIGH

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| LocalAI | v3.11.0 | LLM inference server (OpenAI-compatible API) | Drop-in OpenAI API replacement; native GGUF/llama.cpp backend; single binary deployment; no Docker dependency; active development (3 major releases Jan-Feb 2026) | HIGH |
| Devstral Small 2 24B | Instruct-2512 (Dec 2025) | Coding-focused SLM | Best-in-class open SWE model at 24B params; 68% SWE-bench Verified; Apache 2.0 license; purpose-built for agentic coding with tool-calling support | HIGH |
| Q4_K_M GGUF quantization | bartowski quant | Size/quality tradeoff for CPU inference | 14.3 GB file size; ~75% size reduction vs FP16; <3% quality loss; industry-standard "practical default" for CPU deployment | HIGH |
| Nginx | 1.24.x (Ubuntu 24.04 repo) | TLS termination + basic auth + reverse proxy | LocalAI has no built-in TLS (issue #1295 closed as "not planned"); Nginx is the standard reverse proxy for this pattern; handles SSE streaming, CORS, auth in one layer | HIGH |
| Ubuntu 24.04 LTS (Noble) | 24.04.x | Base OS for appliance image | LTS support until 2029; standard OpenNebula marketplace base; cloud-init compatible; one-context packages available | HIGH |
| Packer | v1.15.0 | QCOW2 image builder | Latest stable (Feb 2026); QEMU plugin v1.1.4 for KVM image builds; proven pattern from flower-opennebula project | HIGH |

### Supporting Libraries & Tools

| Library/Tool | Version | Purpose | When to Use |
|--------------|---------|---------|-------------|
| OpenNebula context packages | 6.10+ | VM contextualization (networking, SSH keys, user params) | Always -- required for marketplace appliance integration |
| one-appliance framework | latest from one-apps repo | Three-stage appliance lifecycle (install/configure/bootstrap) | Always -- provides service_install, service_configure, service_bootstrap hooks |
| openssl | 3.0.x (Ubuntu 24.04 repo) | Self-signed TLS certificate generation at boot | Default TLS mode; generated during service_configure with VM hostname/IP as SAN |
| certbot | 2.9.x (Ubuntu 24.04 repo) | Let's Encrypt TLS certificates | Optional; only when ONEAPP_SLM_TLS_MODE=letsencrypt and VM has public DNS |
| apache2-utils | 2.4.x (Ubuntu 24.04 repo) | htpasswd generation for basic auth | Always -- generates /etc/nginx/.htpasswd during configure stage |
| curl | 8.5.x (Ubuntu 24.04 repo) | Model download from HuggingFace during image build | Packer build phase only; model is baked into image, not downloaded at boot |
| jq | 1.7.x (Ubuntu 24.04 repo) | JSON parsing for health checks and API testing | Runtime health checks and appliance test suite |

### Development & Build Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Packer QEMU plugin | v1.1.4 -- KVM image builder | `packer init` auto-installs; uses `accelerator = "kvm"` on build host |
| cloud-localds | Seed ISO for Packer SSH bootstrap | From `cloud-image-utils` package; creates cloud-init NoCloud datasource |
| qemu-img | QCOW2 image manipulation | Resize base image to 30GB+ before build (model alone is 14.3 GB) |
| shellcheck | Appliance script linting | Lint all .sh files before commit; catches quoting bugs, unset vars |

## Installation

### Packer Build Phase (baked into image)

```bash
# Download LocalAI binary (during Packer provisioning)
curl -Lo /opt/local-ai/local-ai \
  "https://github.com/mudler/LocalAI/releases/download/v3.11.0/local-ai-Linux-x86_64"
chmod +x /opt/local-ai/local-ai

# Download model (during Packer provisioning -- ~14.3 GB)
curl -Lo /opt/local-ai/models/devstral-small-2-24b-q4km.gguf \
  "https://huggingface.co/bartowski/mistralai_Devstral-Small-2-24B-Instruct-2512-GGUF/resolve/main/mistralai_Devstral-Small-2-24B-Instruct-2512-Q4_K_M.gguf"

# System packages (during Packer provisioning)
apt-get install -y nginx apache2-utils openssl jq
```

### Runtime Configuration (applied at VM boot via contextualization)

```bash
# LocalAI systemd unit: /etc/systemd/system/local-ai.service
# Nginx config: /etc/nginx/sites-available/slm-copilot
# Model YAML: /opt/local-ai/models/devstral.yaml
# TLS certs: /etc/ssl/slm-copilot/ (generated at configure time)
# Basic auth: /etc/nginx/.htpasswd (generated at configure time)
```

## Key Configuration Files

### LocalAI Model YAML (/opt/local-ai/models/devstral.yaml)

```yaml
name: devstral
backend: llama-cpp
parameters:
  model: devstral-small-2-24b-q4km.gguf
  temperature: 0.15
  top_p: 0.9

# CPU optimization -- critical for performance
context_size: 8192        # Start conservative; 256K native but RAM-hungry on CPU
threads: 0                # 0 = auto-detect physical cores
mmap: true                # Memory-map model file; faster load, lower RSS
mmlock: false             # Don't lock in RAM; let OS manage pages
```

**Context size rationale:** Devstral supports 256K tokens natively, but on CPU each context token costs RAM. At Q4_K_M, 8K context requires ~16 GB RAM (14.3 GB model + ~2 GB KV cache). Scaling to 32K would need ~20 GB. Default to 8192 and let operators increase via ONEAPP_SLM_CONTEXT_SIZE.

### LocalAI systemd unit (/etc/systemd/system/local-ai.service)

```ini
[Unit]
Description=LocalAI LLM Inference Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/local-ai/local-ai.env
ExecStart=/opt/local-ai/local-ai run \
  --address 127.0.0.1:8080 \
  --models-path /opt/local-ai/models \
  --threads ${LOCALAI_THREADS} \
  --context-size ${LOCALAI_CONTEXT_SIZE}
Restart=on-failure
RestartSec=10
LimitNOFILE=65535
# Model loading can take 30-60s on CPU
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
```

### Nginx reverse proxy (/etc/nginx/sites-available/slm-copilot)

```nginx
server {
    listen 443 ssl;
    server_name _;

    ssl_certificate     /etc/ssl/slm-copilot/cert.pem;
    ssl_certificate_key /etc/ssl/slm-copilot/key.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;

    # Basic auth
    auth_basic "SLM-Copilot API";
    auth_basic_user_file /etc/nginx/.htpasswd;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;

        # SSE streaming -- CRITICAL for chat completions
        proxy_buffering off;
        proxy_cache off;
        proxy_set_header X-Accel-Buffering no;
        proxy_set_header Connection '';
        proxy_read_timeout 600s;    # Long inference on CPU

        # CORS headers for web clients
        add_header Access-Control-Allow-Origin * always;
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Authorization, Content-Type" always;

        if ($request_method = OPTIONS) {
            return 204;
        }
    }

    # Health check endpoint (no auth required)
    location /readyz {
        auth_basic off;
        proxy_pass http://127.0.0.1:8080/readyz;
    }
}

# HTTP -> HTTPS redirect
server {
    listen 80;
    server_name _;
    return 301 https://$host$request_uri;
}
```

## Alternatives Considered

| Category | Recommended | Alternative | Why Not Alternative |
|----------|-------------|-------------|---------------------|
| Inference server | LocalAI (binary) | Ollama | Ollama is simpler but less configurable; no YAML model configs; harder to tune context_size/threads independently; LocalAI's OpenAI API compatibility is more complete |
| Inference server | LocalAI (binary) | llama.cpp server | Raw llama-server has no model gallery, no multi-model support, no OpenAI function calling; LocalAI wraps llama.cpp with production features |
| Inference server | LocalAI (binary) | vLLM | vLLM is GPU-focused; CPU support is experimental; heavy Python dependency; overkill for single-model single-user |
| Inference server | LocalAI (binary) | LocalAI (Docker) | Docker adds 300-500MB overhead + Docker daemon dependency; binary is simpler for appliance pattern; one fewer failure mode |
| Inference server | LocalAI (binary) | LocalAI (install.sh) | Install script is broken per issue #8032 (Jan 2026); produces misconfigured installations; binary download is the recommended path |
| Model | Devstral Small 2 24B | Qwen2.5-Coder-32B | 32B is too large for comfortable CPU inference; needs 20+ GB model file + KV cache; Devstral 24B is purpose-built for SWE |
| Model | Devstral Small 2 24B | Codestral 22B (original) | Superseded by Devstral 2; worse SWE-bench scores; non-permissive license |
| Model | Devstral Small 2 24B | DeepSeek-Coder-V2 | Larger model (236B MoE); not practical for CPU-only; heavier RAM footprint even at Q4 |
| Model | Devstral Small 2 24B | Qwen2.5-Coder-7B | Too small for complex agentic coding; noticeably worse code quality at 7B |
| Quantization | Q4_K_M | Q5_K_M | 16.8 GB file = needs 24+ GB RAM with context; marginal quality gain (<1%) not worth the RAM cost |
| Quantization | Q4_K_M | Q3_K_M | 11.5 GB saves 3 GB RAM but measurable quality drop; Q4_K_M is the sweet spot |
| Quantization | Q4_K_M | IQ4_XS | 12.8 GB is slightly smaller but less widely tested; Q4_K_M is the community standard |
| Reverse proxy | Nginx | Caddy | Caddy auto-TLS is nice but adds Go runtime; Nginx is already in Ubuntu repos; team has Nginx experience from flower project |
| Reverse proxy | Nginx | Traefik | Overkill for single-backend proxy; container-native design doesn't fit bare-metal appliance |
| Auth | Nginx basic auth | LocalAI API key | LocalAI API key has no user management; basic auth integrates with Nginx TLS; operators can add LDAP/OAuth later via Nginx modules |
| GGUF source | bartowski quant | unsloth quant | Both are high quality; bartowski provides the widest range of quant options and consistent naming; either works |
| GGUF source | bartowski quant | lmstudio-community | Also fine; bartowski is slightly more established for GGUF quantizations |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| LocalAI install.sh script | Broken since Jan 2026 (issue #8032); produces misconfigured installations | Direct binary download from GitHub releases |
| LocalAI Docker deployment | Adds Docker daemon overhead, complexity, and failure mode to appliance | Native binary with systemd |
| GPU-dependent backends (vLLM, TensorRT-LLM) | Appliance is explicitly CPU-only; GPU backends add massive dependencies | LocalAI with llama-cpp backend |
| FP16/BF16 model weights | 47.2 GB for Devstral BF16; needs 64+ GB RAM; impractical for target VMs | Q4_K_M quantization (14.3 GB) |
| context_size > 32768 on CPU | KV cache memory scales linearly; 256K context would need 50+ GB RAM on CPU | Default 8192, max 32768 with 64GB RAM |
| LocalAI WebUI in production | Exposes model management and settings; security risk if not isolated | Disable with LOCALAI_DISABLE_WEBUI=true; expose only API via Nginx |
| Let's Encrypt as default TLS | Requires public DNS and port 80 access; many OpenNebula VMs are private-network | Self-signed as default; Let's Encrypt as optional mode |
| CORS wildcard in production | `*` allows any origin; fine for dev but risky in production | Configure specific origins via ONEAPP_SLM_CORS_ORIGINS or use Nginx to restrict |

## Stack Patterns by Variant

**If VM has >= 32 GB RAM (recommended):**
- Use context_size: 16384 (16K) for better code understanding
- Set watchdog_idle_timeout to 0 (never unload model; reload takes 30-60s)
- Single model, single user scenario works well

**If VM has exactly 20-24 GB RAM (minimum viable):**
- Use context_size: 4096 (4K) to fit within memory constraints
- Model (14.3 GB) + KV cache (~1 GB at 4K) + OS (~2 GB) = ~18 GB
- Tight but workable; no room for concurrent requests

**If VM has >= 64 GB RAM (power user):**
- Use context_size: 32768 (32K) for large codebase understanding
- Consider Q5_K_M (16.8 GB) for marginally better quality
- Could run 2 concurrent requests with parallel_backend_requests enabled

**If operator wants multi-model:**
- Set max_active_backends: 1 (swap models on demand)
- Only one model loaded at a time to conserve RAM
- Add a smaller model (7B) for quick completions alongside Devstral for complex tasks

## Version Compatibility

| Component | Compatible With | Notes |
|-----------|-----------------|-------|
| LocalAI v3.11.0 | GGUF format (llama.cpp b4000+) | Ensure GGUF version matches llama.cpp bundled in LocalAI |
| Devstral-Small-2-24B Q4_K_M | LocalAI llama-cpp backend | Standard GGUF; auto-detected by LocalAI if placed in models dir |
| Nginx 1.24.x | Ubuntu 24.04 LTS | From default Ubuntu repos; no PPA needed |
| Packer v1.15.0 | QEMU plugin >= 1.1.3 | Use `required_plugins` block with `version = ">= 1.1.4"` |
| Ubuntu 24.04 | OpenNebula context 6.10+ | one-context-linux package from OpenNebula repos |
| Cline VS Code extension | OpenAI-compatible API | Configure: Base URL = `https://<vm-ip>/v1`, API Key = basic auth password, Model ID = `devstral` |

## Hardware Sizing Guide

| Profile | vCPUs | RAM | Disk | Expected Performance | Use Case |
|---------|-------|-----|------|---------------------|----------|
| Minimum | 8 | 24 GB | 40 GB | ~1-2 tok/s generation | Barely usable; for testing only |
| Recommended | 16 | 32 GB | 50 GB | ~3-5 tok/s generation | Single developer, acceptable latency |
| Optimal | 32 | 64 GB | 50 GB | ~5-10 tok/s generation | Comfortable single-user experience |

**Performance context:** CPU-only inference of a 24B Q4_K_M model is fundamentally slow compared to GPU. A benchmark of magistral:24b-small Q4_K_M on a laptop with partial CPU involvement showed 3.66 tok/s. Pure CPU with 16+ cores should achieve 3-5 tok/s for generation (prompt processing is faster). This is usable for coding assistance where you wait a few seconds per response, but not for real-time chat.

**Disk sizing:** Model file (14.3 GB) + LocalAI binary (~200 MB) + OS (~4 GB) + Nginx/tools (~100 MB) + logs/temp (~2 GB) = ~21 GB minimum. Use 40-50 GB to allow headroom for updates and potential second model.

## OpenNebula Contextualization Parameters

These ONEAPP_ parameters are exposed to cloud users through the VM template CONTEXT section:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `ONEAPP_SLM_ADMIN_PASSWORD` | (generated) | Basic auth password for API access |
| `ONEAPP_SLM_CONTEXT_SIZE` | 8192 | Model context window in tokens |
| `ONEAPP_SLM_THREADS` | 0 (auto) | CPU threads for inference (0 = all physical cores) |
| `ONEAPP_SLM_TLS_MODE` | selfsigned | TLS mode: selfsigned, letsencrypt, or custom |
| `ONEAPP_SLM_TLS_CERT` | (empty) | Custom TLS certificate (base64 PEM) |
| `ONEAPP_SLM_TLS_KEY` | (empty) | Custom TLS private key (base64 PEM) |
| `ONEAPP_SLM_DOMAIN` | (empty) | Domain name for Let's Encrypt and certificate SAN |
| `ONEAPP_SLM_CORS_ORIGINS` | * | Allowed CORS origins (comma-separated) |
| `ONEAPP_SLM_MODEL_TEMPERATURE` | 0.15 | Model temperature (lower = more deterministic for code) |

## Sources

- [LocalAI GitHub Releases](https://github.com/mudler/LocalAI/releases) -- v3.11.0 confirmed as latest (Feb 7, 2026) | HIGH confidence
- [LocalAI Installation Docs](https://localai.io/installation/linux/) -- binary download method, install.sh warning | HIGH confidence
- [LocalAI Model Configuration](https://localai.io/advanced/model-configuration/) -- full YAML schema, context_size default 512, threads config | HIGH confidence
- [LocalAI Runtime Settings](https://localai.io/features/runtime-settings/) -- environment variables, CORS config | HIGH confidence
- [LocalAI CLI Reference](https://localai.io/reference/cli-reference/) -- all CLI flags and env vars | HIGH confidence
- [LocalAI TLS Issue #1295](https://github.com/mudler/LocalAI/issues/1295) -- no built-in TLS, closed as "not planned" | HIGH confidence
- [LocalAI Install Script Issue #8032](https://github.com/mudler/LocalAI/issues/8032) -- install.sh broken, opened Jan 2026 | HIGH confidence
- [Mistral Devstral-Small-2-24B HuggingFace](https://huggingface.co/mistralai/Devstral-Small-2-24B-Instruct-2512) -- 256K context, Apache 2.0, Dec 2025, SWE-bench 68% | HIGH confidence
- [bartowski GGUF Quantizations](https://huggingface.co/bartowski/mistralai_Devstral-Small-2-24B-Instruct-2512-GGUF) -- Q4_K_M = 14.3 GB, full quant range | HIGH confidence
- [Cline OpenAI-Compatible Config](https://docs.cline.bot/provider-config/openai-compatible) -- Base URL, API Key, Model ID fields | HIGH confidence
- [Packer GitHub Releases](https://github.com/hashicorp/packer/releases) -- v1.15.0, Feb 4 2026 | HIGH confidence
- [Packer QEMU Plugin](https://developer.hashicorp.com/packer/integrations/hashicorp/qemu) -- v1.1.4, QCOW2 builder | HIGH confidence
- [24B LLM CPU Benchmark](https://aimuse.blog/article/2025/06/13/the-real-world-speed-of-ai-benchmarking-a-24b-llm-on-local-hardware-vs-high-end-cloud-gpus) -- 3.66 tok/s with partial CPU (magistral 24B Q4_K_M) | MEDIUM confidence (different but comparable model)
- [LLM Quantization Guide](https://localaimaster.com/blog/quantization-explained) -- Q4_K_M quality retention, size reduction ratios | MEDIUM confidence
- [Nginx AI Proxy Blog](https://blog.nginx.org/blog/using-nginx-as-an-ai-proxy) -- SSE streaming config, proxy_buffering off | MEDIUM confidence

---
*Stack research for: CPU-only AI coding assistant (OpenNebula marketplace appliance)*
*Researched: 2026-02-13*
