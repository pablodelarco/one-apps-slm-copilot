# SLM-Copilot: Sovereign AI Coding Assistant

Your code never leaves your infrastructure. Deploy a private AI coding copilot on any VM — no GPU, no cloud APIs, no subscriptions.

| | |
|---|---|
| **Model** | Devstral Small 2 (24B, Q4_K_M) by Mistral AI |
| **Inference** | CPU-only via Ollama — 32 GB RAM minimum |
| **Security** | TLS + token auth out of the box |
| **API** | OpenAI-compatible — works with aider, Cline, Continue, and more |
| **License** | 100% open-source (Apache 2.0 / MIT) |

## Quick Start

```bash
# 1. Import the appliance from the OpenNebula marketplace (Storage → Apps → "SLM-Copilot")
# 2. Create a VM: 32 GB RAM, 16 vCPUs minimum
# 3. Boot and wait ~2 min, then SSH in:
cat /etc/one-appliance/config   # shows your API endpoint and password
```

Connect with [aider](https://aider.chat):

```bash
pip install aider-chat

aider --openai-api-key <password> \
      --openai-api-base https://<vm-ip>/v1 \
      --model openai/devstral-small-2 \
      --no-show-model-warnings
```

Any OpenAI-compatible client works with the same base URL, API key, and model ID.

## Configuration

Set these in the VM template before booting (all optional, re-read on every reboot):

| Variable | Default | Description |
|----------|---------|-------------|
| `ONEAPP_COPILOT_PASSWORD` | *(auto-generated)* | API password |
| `ONEAPP_COPILOT_DOMAIN` | *(empty)* | FQDN for Let's Encrypt TLS (self-signed if empty) |
| `ONEAPP_COPILOT_CONTEXT_SIZE` | `32768` | Token context window (512–131072) |
| `ONEAPP_COPILOT_THREADS` | `0` | CPU threads for inference (`0` = all cores) |

## Troubleshooting

| Problem | Check |
|---------|-------|
| Service won't start | VM needs at least 32 GB RAM |
| Slow inference | Add more vCPUs; CPU must support AVX2 |
| Let's Encrypt fails | DNS must resolve and port 80 must be reachable |
| Client can't connect | Port 443 open? Test: `curl -k https://<vm-ip>/readyz` |

Logs: `journalctl -u ollama` (inference) · `journalctl -u nginx` (proxy) · `/etc/one-appliance/config` (credentials)

## License

Apache License 2.0. Built with open-source components by [Mistral AI](https://mistral.ai) (Paris) and [OpenNebula](https://opennebula.io) (Madrid).
