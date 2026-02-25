# SLM-Copilot: Sovereign AI Coding Assistant

Your code never leaves your infrastructure. Deploy a private AI coding copilot on any VM -- no GPU, no cloud APIs, no subscriptions.

| | |
|---|---|
| **Model** | Devstral Small 2 (24B, Q4_K_M) by Mistral AI |
| **Inference** | CPU-only via llama-server (llama.cpp) -- 32 GB RAM minimum |
| **Security** | Native TLS + Bearer token auth out of the box |
| **API** | OpenAI-compatible -- works with aider, Cline, Continue, and more |
| **Metrics** | Built-in Prometheus endpoint at /metrics |
| **License** | 100% open-source (Apache 2.0 / MIT) |

## Quick Start

```bash
# 1. Import the appliance from the OpenNebula marketplace (Storage > Apps > "SLM-Copilot")
# 2. Create a VM: 32 GB RAM, 16 vCPUs, CPU model = host-passthrough
# 3. Boot and wait ~2 min, then SSH in:
cat /etc/one-appliance/config   # shows your API endpoint and API key
```

Connect with [aider](https://aider.chat):

```bash
pip install aider-chat

aider --openai-api-key <api-key> \
      --openai-api-base https://<vm-ip>:8443/v1 \
      --model openai/devstral-small-2 \
      --no-show-model-warnings
```

Any OpenAI-compatible client works with the same base URL, API key, and model ID.

## Configuration

Set these in the VM template before booting (all optional, re-read on every reboot):

| Variable | Default | Description |
|----------|---------|-------------|
| `ONEAPP_COPILOT_PASSWORD` | *(auto-generated)* | API key (Bearer token) |
| `ONEAPP_COPILOT_DOMAIN` | *(empty)* | FQDN for Let's Encrypt TLS (self-signed if empty) |
| `ONEAPP_COPILOT_CONTEXT_SIZE` | `32768` | Token context window (512-131072) |
| `ONEAPP_COPILOT_THREADS` | `0` | CPU threads for inference (`0` = all cores) |
| `ONEAPP_COPILOT_MODEL` | `devstral` | `devstral` (built-in) or a direct GGUF URL from Hugging Face |
| `ONEAPP_COPILOT_LB_BACKENDS` | *(empty)* | Load balancer backends (`key@host:port`, comma-separated). Empty = standalone |

## Load Balancing Across Zones

Set `ONEAPP_COPILOT_LB_BACKENDS` on one VM to turn it into a load balancer that distributes requests across multiple SLM-Copilot instances. The `key` in each entry is the remote VM's `ONEAPP_COPILOT_PASSWORD` (the API password / Bearer token).

```
                      Developers
                          │
                          ▼
               ┌─────────────────────┐
               │  LB VM (Madrid)     │
               │  LiteLLM :8443      │
               │  + local llama-svr  │
               └──┬──────────┬───────┘
                  │          │
         ┌────────▼──┐  ┌───▼────────┐
         │ Paris VM  │  │ Berlin VM  │
         │ standalone│  │ standalone │
         │ :8443     │  │ :8443      │
         └───────────┘  └────────────┘
```

### Setup

1. **Deploy standalone VMs** in each zone — standard SLM-Copilot VMs, no special config. Note each VM's IP and `ONEAPP_COPILOT_PASSWORD` (check with `cat /etc/one-appliance/config`).

2. **Ensure network reachability** on port 8443 between all VMs. Options:
   - [Tailscale](https://tailscale.com) (recommended) — automatic mesh, use 100.x.y.z IPs
   - WireGuard, VPN, or public IPs with port 8443 open

3. **Deploy the LB VM** with backends pointing at the remote VMs:
   ```
   ONEAPP_COPILOT_LB_BACKENDS=sk-paris-pw@100.64.1.10:8443,sk-berlin-pw@100.64.1.20:8443
   ```
   Format: `<remote_api_password>@<host>:<port>` — comma-separated. The LB VM's own llama-server is automatically included as a local backend.

4. **Give developers the LB VM's endpoint** — they configure `https://<lb-vm-ip>:8443/v1` with the LB VM's own API key. They don't need to know about the backends.

### Verify

```bash
# On the LB VM:
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

LiteLLM uses least-busy routing with automatic failover (30s cooldown after 2 consecutive failures). See [`appliances/slm-copilot/README.md`](appliances/slm-copilot/README.md) for full technical details.

## Troubleshooting

| Problem | Check |
|---------|-------|
| Service won't start | VM needs at least 32 GB RAM |
| Slow inference | Add more vCPUs; CPU must support AVX2. Set CPU model to `host-passthrough` in the VM template |
| Inference hangs | VM CPU model must be `host-passthrough` (not `qemu64`). Without it, AVX2/AVX-512 instructions are not exposed to the guest |
| Let's Encrypt fails | DNS must resolve and port 80 must be reachable |
| Client can't connect | Port 8443 open? Test: `curl -k https://<vm-ip>:8443/health` |

Logs: `journalctl -u slm-copilot` (inference) / `/etc/one-appliance/config` (credentials)

## License

Apache License 2.0. Built with open-source components by [Mistral AI](https://mistral.ai) (Paris) and [OpenNebula](https://opennebula.io) (Madrid).
