# SLM-Copilot: Sovereign AI Coding Assistant

One-click deployment of a sovereign, CPU-only AI coding copilot from the OpenNebula marketplace. Your code never leaves your infrastructure — no GPU required, no cloud API subscriptions.

## Features

- **Fully sovereign** — runs entirely on your infrastructure, no external API calls
- **CPU-only inference** — works on any standard VM with enough RAM, no GPU needed
- **Pre-loaded model** — Devstral Small 2 (24B, Q4_K_M) by Mistral AI, optimized for code
- **Secure by default** — TLS encryption + token-based authentication out of the box
- **OpenAI-compatible API** — works with aider, Cline, Continue, and any OpenAI-compatible client
- **100% open-source** — Apache 2.0 model (Mistral AI), MIT inference engine (Ollama), Apache 2.0 platform (OpenNebula)

## Installation

1. In Sunstone, go to **Storage → Apps** and search for **SLM-Copilot**
2. Import the appliance (this downloads the ~15 GB image)
3. Create a VM from the imported template with **32 GB RAM** and **16 vCPUs** (minimum)
4. Boot the VM and wait ~2 minutes for the model to load into memory
5. SSH into the VM and check connection details:
   ```
   cat /etc/one-appliance/config
   ```

## Configuration

Set these context variables in the VM template before booting (all optional):

| Variable | Default | Description |
|----------|---------|-------------|
| `ONEAPP_COPILOT_PASSWORD` | *(auto-generated)* | API password. If empty, a random password is generated on first boot. |
| `ONEAPP_COPILOT_DOMAIN` | *(empty)* | FQDN for Let's Encrypt TLS. If empty, uses a self-signed certificate. |
| `ONEAPP_COPILOT_CONTEXT_SIZE` | `32768` | Token context window (512–131072). Larger values use more RAM. |
| `ONEAPP_COPILOT_THREADS` | `0` | CPU threads for inference. `0` = auto-detect all cores. |

All variables are re-read on every boot — change a value and reboot to apply.

## Connecting with aider

[aider](https://aider.chat) is an open-source AI coding assistant that runs in the terminal.

1. Install aider: `pip install aider-chat`
2. Configure it to point at your appliance:
   ```
   aider --openai-api-key <password> \
         --openai-api-base https://<vm-ip>/v1 \
         --model openai/devstral-small-2 \
         --no-show-model-warnings
   ```

Replace `<vm-ip>` and `<password>` with the values from `cat /etc/one-appliance/config` on the VM.

Any OpenAI-compatible client (Cline, Continue, etc.) can also connect using the same base URL, API key, and model ID.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Service not starting | Ensure VM has at least 32 GB RAM |
| Slow inference | Add more vCPUs; ensure CPU supports AVX2 |
| Let's Encrypt failed | Check DNS and that port 80 is reachable |
| Client can't connect | Verify port 443 is open; test with `curl -k https://<vm-ip>/readyz` |

Logs: `journalctl -u ollama` (inference) · `journalctl -u nginx` (proxy) · `/etc/one-appliance/config` (credentials)

## License

Apache License 2.0. Built with open-source components by European companies: [Mistral AI](https://mistral.ai) (Paris), [OpenNebula](https://opennebula.io) (Madrid).
