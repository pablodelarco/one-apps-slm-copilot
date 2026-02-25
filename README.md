# SLM-Copilot: Sovereign AI Coding Assistant

Your code never leaves your infrastructure. Deploy a private AI coding copilot on any VM -- no GPU, no cloud APIs, no subscriptions.

| | |
|---|---|
| **Model** | Devstral Small 2 (24B, Q4\_K\_M) by Mistral AI |
| **Inference** | CPU-only via llama-server (llama.cpp) -- 32 GB RAM minimum |
| **Security** | Native TLS + Bearer token auth out of the box |
| **API** | OpenAI-compatible -- works with [aider](https://aider.chat), [OpenCode](https://opencode.ai), and any OpenAI client |
| **Metrics** | Built-in Prometheus endpoint at /metrics |
| **License** | 100% open-source (Apache 2.0 / MIT) |

## Architecture

### Standalone mode (default)

```
Developer Machine            OpenNebula VM (32 GB RAM, 16 vCPU)
+------------------+         +------------------------------------------+
| aider / OpenCode |  HTTPS  | llama-server (TLS + Bearer Auth)  :8443 |
| / any OAI client |-------->|   |                                      |
+------------------+         |   v                                      |
                             | Devstral Small 2 (24B Q4_K_M, ~14 GB)   |
                             |                                          |
                             | Built-in: CORS, Prometheus /metrics      |
                             +------------------------------------------+
```

The client sends OpenAI-compatible API requests over HTTPS to port 8443. llama-server handles TLS termination (self-signed or Let's Encrypt), validates the Bearer token, and returns chat completions (streaming or non-streaming). All inference runs on CPU.

### Load balancer mode (optional)

When you set `ONEAPP_COPILOT_LB_BACKENDS`, a [LiteLLM](https://github.com/BerriAI/litellm) proxy sits in front of the local llama-server and distributes requests across multiple backends:

```
Client --> :8443 (LiteLLM proxy, TLS + auth)
              |
              +--> localhost:8444  (local llama-server, plain HTTP)
              +--> https://10.0.1.10:8443  (remote SLM-Copilot VM)
              +--> https://10.0.1.11:8443  (remote SLM-Copilot VM)
```

LiteLLM picks a backend using "least-busy" routing, forwards the request, and streams the response back. The client sees a single endpoint.

**Why load balance?** A single llama-server on CPU can take 10-60+ seconds per response with a 24B model depending on output length. With LB you can scale horizontally (3-5 VMs = 3-5 developers served simultaneously), use one endpoint, get automatic failover (30s cooldown after 2 consecutive failures), and distribute across datacenters.

**Components:**

- **llama-server** -- llama.cpp inference server with native TLS, API key auth, CORS, and Prometheus metrics. Compiled with GGML\_CPU\_ALL\_VARIANTS for automatic SIMD detection. Listens on port 8443 (standalone) or 127.0.0.1:8444 (LB mode).
- **Devstral Small 2** -- 24B coding model by Mistral AI, quantized to Q4\_K\_M (~14 GB GGUF).
- **LiteLLM proxy** *(LB mode only)* -- OpenAI-compatible proxy with least-busy routing, automatic failover, and TLS termination. Installed in `/opt/litellm` Python venv.

## Quick Start

### Prerequisites

- OpenNebula 6.10+ with KVM hypervisor
- VM template: 32 GB RAM, 16 vCPU, 60 GB disk (minimum), **CPU model: `host-passthrough`**
- Network: port 8443 open (and port 80 if using Let's Encrypt)

> **Important:** The VM template must use `host-passthrough` CPU model so that AVX2/AVX-512 instructions are exposed to the guest. Without this, llama.cpp inference will hang.

### Example VM template

If importing from the marketplace, the template is created automatically. For manual setup or customization, here's the OpenNebula template:

```
CPU     = "16"
MEMORY  = "32768"
VCPU    = "16"

CPU_MODEL = [ MODEL = "host-passthrough" ]

CONTEXT = [
    NETWORK                        = "YES",
    SSH_PUBLIC_KEY                  = "$USER[SSH_PUBLIC_KEY]",
    ONEAPP_COPILOT_AI_MODEL        = "Devstral Small 24B (built-in)",
    ONEAPP_COPILOT_CONTEXT_SIZE    = "32768",
    ONEAPP_COPILOT_CPU_THREADS     = "0",
    ONEAPP_COPILOT_API_PASSWORD    = "",
    ONEAPP_COPILOT_TLS_DOMAIN      = "",
    ONEAPP_COPILOT_LB_BACKENDS     = ""
]

DISK = [ IMAGE = "SLM-Copilot" ]

NIC = [ NETWORK = "your-network" ]
NIC_DEFAULT = [ MODEL = "virtio" ]

GRAPHICS = [ LISTEN = "0.0.0.0", TYPE = "VNC" ]
```

Leave `ONEAPP_COPILOT_API_PASSWORD` empty for auto-generation. Set `ONEAPP_COPILOT_LB_BACKENDS` only if using [load balancing](#load-balancing-across-zones).

### Steps

1. **Import** the appliance from the OpenNebula marketplace (or build from source with `make build`)
2. **Create a VM** from the template, optionally setting context variables (see [Configuration](#configuration))
3. **Wait for boot** -- service startup takes approximately 2 minutes (model loading)
4. **Check connection details** by SSHing into the VM:
   ```bash
   cat /etc/one-appliance/config
   ```
5. **Connect a client** -- replace `<vm-ip>` and `<api-key>` with values from the report file:

   **aider** (chat-based coding assistant):
   ```bash
   pip install aider-chat

   aider --openai-api-key <api-key> \
         --openai-api-base https://<vm-ip>:8443/v1 \
         --model openai/devstral-small-2 \
         --no-show-model-warnings
   ```

   **OpenCode** (autonomous coding agent with tool use):
   ```bash
   curl -fsSL https://opencode.ai/install | bash
   ```
   Create `opencode.json` in your project root:
   ```json
   {
     "$schema": "https://opencode.ai/config.json",
     "provider": {
       "slm-copilot": {
         "npm": "@ai-sdk/openai-compatible",
         "name": "SLM-Copilot",
         "options": {
           "baseURL": "https://<vm-ip>:8443/v1",
           "apiKey": "{env:SLM_COPILOT_API_KEY}"
         },
         "models": {
           "devstral-small-2": {
             "name": "Devstral Small 24B"
           }
         }
       }
     },
     "model": {
       "default": "slm-copilot/devstral-small-2"
     }
   }
   ```
   Then set your API key and run:
   ```bash
   export SLM_COPILOT_API_KEY=<api-key>
   export NODE_TLS_REJECT_UNAUTHORIZED=0   # only for self-signed certs
   opencode
   ```

   Any other OpenAI-compatible client works with the same base URL, API key, and model ID `devstral-small-2`.

6. **Validate** the deployment:
   ```bash
   make test ENDPOINT=https://<vm-ip>:8443 PASSWORD=<api-key>
   ```

## Configuration

All configuration is via OpenNebula context variables, set in the VM template. All are re-read on every boot -- change a value and reboot to apply.

| Variable | Default | Description |
|----------|---------|-------------|
| `ONEAPP_COPILOT_AI_MODEL` | `Devstral Small 24B (built-in)` | AI model from the built-in catalog |
| `ONEAPP_COPILOT_CONTEXT_SIZE` | `32768` | Token context window (8192, 16384, or 32768) |
| `ONEAPP_COPILOT_CPU_THREADS` | `0` *(auto-detect)* | CPU threads for inference (`0` = all cores) |
| `ONEAPP_COPILOT_API_PASSWORD` | *(auto-generated)* | API key (Bearer token). Auto-generated if empty |
| `ONEAPP_COPILOT_TLS_DOMAIN` | *(empty)* | FQDN for Let's Encrypt (self-signed if empty) |
| `ONEAPP_COPILOT_LB_BACKENDS` | *(empty)* | Remote backends: `key@host:port,key@host:port`. Empty = standalone |

### Model catalog

The default Devstral Small 24B is baked into the image. Other models are downloaded from Hugging Face on first boot:

| Model | Size (Q4\_K\_M) | RAM Usage | Best For |
|-------|-----------------|-----------|----------|
| Devstral Small 24B (built-in) | 14.3 GB | ~16 GB | Coding (Mistral, latest) |
| Codestral 22B | 13.3 GB | ~15 GB | Coding (Mistral flagship) |
| Mistral Nemo 12B | 7.5 GB | ~10 GB | Reasoning + coding |
| Codestral Mamba 7B | 4.0 GB | ~6 GB | Coding (SSM architecture) |
| Mistral 7B | 4.4 GB | ~6 GB | General purpose |

## Load Balancing Across Zones

Set `ONEAPP_COPILOT_LB_BACKENDS` on one VM to turn it into a load balancer. The `key` in each entry is the remote VM's `ONEAPP_COPILOT_API_PASSWORD`.

```
                    ┌──────────────────────────────────────────┐
                    │            OpenNebula Federation          │
                    │         (shared user DB, SSO, ACLs)       │
                    └───────┬───────────────┬──────────────┬────┘
                            │               │              │
               ┌────────────┴──┐   ┌────────┴────────┐  ┌─┴──────────────┐
               │  Zone: Madrid │   │  Zone: Paris    │  │  Zone: Berlin  │
               └──────┬────────┘   └────────┬────────┘  └───────┬────────┘
                      │                     │                    │
              ┌───────┴──────────┐   ┌──────┴───────┐   ┌───────┴───────┐
              │ LB VM (Madrid)   │   │ Paris VM     │   │ Berlin VM     │
              │                  │   │ standalone   │   │ standalone    │
              │  LiteLLM :8443   │   │              │   │               │
              │    │             │   │ llama-server │   │ llama-server  │
              │    ├──► local    │   │ Devstral 24B │   │ Devstral 24B  │
              │    │  llama-svr  │   │ :8443        │   │ :8443         │
              │    │  :8444      │   │              │   │               │
              └────┼─────────────┘   └──────▲───────┘   └───────▲───────┘
                   │                        │                    │
                   └────────────────────────┴────────────────────┘
                        LiteLLM routes to all 3 backends
                        (least-busy, auto-failover)

              Developers ──HTTPS──► Madrid :8443 (single endpoint)
```

### Setup

1. **Deploy standalone VMs** in each zone -- standard SLM-Copilot VMs, no special config. Note each VM's IP and API password (`cat /etc/one-appliance/config`).

2. **Ensure network reachability** on port 8443 between all VMs:
   - [Tailscale](https://tailscale.com) (recommended) -- automatic mesh, use 100.x.y.z IPs
   - WireGuard, VPN, or public IPs with port 8443 open

3. **Deploy the LB VM** with backends:
   ```
   ONEAPP_COPILOT_LB_BACKENDS=sk-paris-pw@100.64.1.10:8443,sk-berlin-pw@100.64.1.20:8443
   ```
   Format: `<remote_api_password>@<host>:<port>` -- comma-separated. The LB VM's own llama-server is automatically included as a local backend.

4. **Give developers the LB VM's endpoint** -- `https://<lb-vm-ip>:8443/v1` with the LB VM's own API key. They don't need to know about the backends.

### Verify

```bash
curl -sk https://127.0.0.1:8443/health/liveliness   # "I'm alive!"
journalctl -u slm-copilot-proxy -f                   # watch routing decisions
```

### Scaling guide

| Team size | Backend VMs | Config |
|-----------|------------|--------|
| 1-2 devs | 1 (standalone, no LB) | Leave `LB_BACKENDS` empty |
| 3-5 devs | 2-3 VMs | `key1@host1:8443,key2@host2:8443` |
| 5-10 devs | 4-5 VMs | Add more `key@host:8443` entries |
| 10+ devs | 5+ VMs | Consider two LB endpoints for redundancy |

## Testing

Validate a running instance:

```bash
make test ENDPOINT=https://<vm-ip>:8443 PASSWORD=<api-key>
```

Runs 7 checks: HTTPS connectivity, health endpoint, auth rejection, auth acceptance, model listing, chat completion (non-streaming), and streaming SSE.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Service won't start | VM needs at least 32 GB RAM. Check: `journalctl -u slm-copilot` |
| Slow inference | Add more vCPUs. Ensure `host-passthrough` CPU model. Check: `grep avx2 /proc/cpuinfo` |
| Inference hangs | CPU model must be `host-passthrough` (not `qemu64`). Set in VM template: CPU Model > `host-passthrough` |
| Let's Encrypt fails | DNS must resolve and port 80 must be reachable. Falls back to self-signed automatically |
| Client can't connect | Port 8443 open? Test: `curl -k https://<vm-ip>:8443/health`. For self-signed cert issues: `OPENAI_API_VERIFY_SSL=false` |
| Out of memory | Reduce `ONEAPP_COPILOT_CONTEXT_SIZE`. 24B model needs ~14 GB + KV cache overhead |

### Log locations

| Log | Location |
|-----|----------|
| Inference server | `journalctl -u slm-copilot` |
| LiteLLM proxy (LB mode) | `journalctl -u slm-copilot-proxy` |
| Application log | `/var/log/one-appliance/slm-copilot.log` |
| Report file | `/etc/one-appliance/config` |

## Performance

| vCPUs | RAM | Context Size | Approx. Speed |
|-------|-----|--------------|---------------|
| 8 | 32 GB | 32K | ~3-5 tok/s |
| 16 | 32 GB | 32K | ~5-10 tok/s |
| 32 | 64 GB | 64K | ~10-15 tok/s |

AVX-512 improves inference speed 20-40% over AVX2-only CPUs. First request after boot is slower due to model loading (~30-60 seconds).

## License

Apache License 2.0. Built with open-source components by [Mistral AI](https://mistral.ai) (Paris) and [OpenNebula](https://opennebula.io) (Madrid).

| Component | License | Maintainer |
|-----------|---------|------------|
| Devstral Small 2 | Apache 2.0 | Mistral AI (Paris) |
| llama.cpp | MIT | ggerganov |
| OpenNebula one-apps | Apache 2.0 | OpenNebula Systems (Madrid) |

## Author

Pablo del Arco, Cloud-Edge Innovation Engineer at [OpenNebula Systems](https://opennebula.io/).
