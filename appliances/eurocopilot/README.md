# EuroCopilot

Sovereign AI coding assistant powered by [Devstral Small 2](https://mistral.ai/news/devstral-2-vibe-cli) (24B, Mistral AI) running on CPU via [llama.cpp](https://github.com/ggerganov/llama.cpp). No GPU required.

Deploy a fully self-contained AI coding copilot as an OpenNebula marketplace appliance. Connect with [aider](https://aider.chat) or any OpenAI-compatible client for AI-assisted coding on your own infrastructure.

## Quick Start

1. Import the EuroCopilot appliance from the OpenNebula marketplace.
2. Instantiate a VM with at least 16 vCPUs, 32 GB RAM, and `CPU_MODEL=host-passthrough`.
3. On first boot the appliance downloads the model, generates a TLS certificate and API key, and starts the inference server.
4. Retrieve the API endpoint and key from `/etc/one-appliance/config` inside the VM.
5. Point aider or any OpenAI-compatible client at `https://<VM_IP>:8443`.

## Contextualization Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `ONEAPP_COPILOT_AI_MODEL` | Yes | `Devstral Small 2 (24B ~14GB built-in)` | AI model selection from catalog |
| `ONEAPP_COPILOT_CONTEXT_SIZE` | No | `16384` | Model context window in tokens |
| `ONEAPP_COPILOT_CPU_THREADS` | No | `0` | CPU threads for inference (0 = auto-detect) |
| `ONEAPP_COPILOT_API_PASSWORD` | No | (auto-generated) | API key / Bearer token |
| `ONEAPP_COPILOT_TLS_DOMAIN` | No | (self-signed) | FQDN for Let's Encrypt certificate |
| `ONEAPP_COPILOT_LB_ENABLED` | No | `NO` | Enable LiteLLM load balancer mode |
| `ONEAPP_COPILOT_LB_BACKENDS` | No | (empty) | Remote backends for load balancing (key@host:port, comma-separated) |
| `ONEAPP_COPILOT_REGISTER_URL` | No | (empty) | Remote LB URL for auto-registration (e.g. https://lb:8443) |
| `ONEAPP_COPILOT_REGISTER_KEY` | No | (empty) | Remote LB master key for auto-registration |
| `ONEAPP_COPILOT_REGISTER_MODEL_NAME` | No | (auto) | Model name override for LB registration |
| `ONEAPP_COPILOT_REGISTER_SITE_NAME` | No | (empty) | Site name for LB backend ID (e.g. poland0) |

## License

Apache 2.0
