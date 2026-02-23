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
