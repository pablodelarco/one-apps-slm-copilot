# EuroCopilot

Sovereign AI coding assistant. Runs [Devstral Small 2](https://mistral.ai/news/devstral-2-vibe-cli) (24B) on CPU via [llama.cpp](https://github.com/ggerganov/llama.cpp). No GPU required.

## Quick Start

1. Import the appliance from the OpenNebula marketplace
2. Create a VM (8+ vCPU, 32 GB RAM, `CPU_MODEL=host-passthrough`)
3. Wait ~2 min for the model to load
4. Get your API key: `ssh root@<vm-ip>` then `cat /etc/one-appliance/config`
5. Connect from VS Code with [Continue](https://continue.dev) or [Cline](https://cline.bot) pointing at `https://<vm-ip>:8443`

## Modes

**Standalone** (default): Single VM serving inference on port 8443 with TLS and API key auth.

**Load Balancer**: Enable `ONEAPP_COPILOT_LB_ENABLED=YES` to run a [LiteLLM](https://litellm.ai) proxy that distributes requests across multiple EuroCopilot VMs with least-busy routing.

**Auto-registration**: Standalone VMs can register themselves with a remote LB on boot via `ONEAPP_COPILOT_REGISTER_URL`.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `ONEAPP_COPILOT_AI_MODEL` | Devstral Small 2 (built-in) | Model selection from catalog |
| `ONEAPP_COPILOT_CONTEXT_SIZE` | 16384 | Context window (tokens) |
| `ONEAPP_COPILOT_CPU_THREADS` | 0 (auto) | CPU threads for inference |
| `ONEAPP_COPILOT_API_PASSWORD` | (auto-generated) | API key / Bearer token |
| `ONEAPP_COPILOT_TLS_DOMAIN` | (self-signed) | FQDN for Let's Encrypt |
| `ONEAPP_COPILOT_LB_ENABLED` | NO | Enable LiteLLM load balancer |
| `ONEAPP_COPILOT_LB_BACKENDS` | (empty) | Static backends (key@host:port) |
| `ONEAPP_COPILOT_REGISTER_URL` | (empty) | Remote LB URL for auto-registration |
| `ONEAPP_COPILOT_REGISTER_KEY` | (empty) | Remote LB master key |
| `ONEAPP_COPILOT_REGISTER_MODEL_NAME` | (auto) | Model name for LB registration |
| `ONEAPP_COPILOT_REGISTER_SITE_NAME` | (empty) | Site name for backend ID |

## Access

| Endpoint | URL | Auth |
|----------|-----|------|
| API | `https://<vm-ip>:8443/v1` | Bearer token |
| Health | `https://<vm-ip>:8443/health` | None |
| Metrics | `https://<vm-ip>:8443/metrics` | None |
| LB Web UI | `https://<vm-ip>:8443/ui` | admin / API key |

## License

Apache 2.0. Model: Devstral Small 2 (Apache 2.0, Mistral AI).

## Author

Pablo del Arco, [OpenNebula Systems](https://opennebula.io).
