# EuroCopilot

Sovereign AI coding assistant. Runs [Devstral Small 2](https://mistral.ai/news/devstral-2-vibe-cli) (24B, Mistral AI) on CPU via [llama.cpp](https://github.com/ggerganov/llama.cpp). No GPU required. OpenAI-compatible API with native TLS and Bearer token auth.

## Quick Start

1. Import the appliance from the OpenNebula marketplace
2. Create a VM: 8+ vCPU, 32 GB RAM, `CPU_MODEL=host-passthrough`
3. Wait ~2 min for the model to load
4. Get your endpoint and API key:
   ```bash
   ssh root@<vm-ip>
   cat /etc/one-appliance/config
   ```
5. Connect from any OpenAI-compatible client:
   ```bash
   curl -sk https://<vm-ip>:8443/v1/chat/completions \
     -H "Authorization: Bearer <api-key>" \
     -H "Content-Type: application/json" \
     -d '{"model":"devstral-small-2","messages":[{"role":"user","content":"Hello"}]}'
   ```

Works with [Continue](https://continue.dev), [Cline](https://cline.bot), [aider](https://aider.chat), or any OpenAI-compatible tool.

## Modes

**Standalone** (default): llama-server on port 8443 with TLS and API key auth.

**Load Balancer**: Set `ONEAPP_COPILOT_LB_ENABLED=YES` to run a [LiteLLM](https://litellm.ai) proxy that distributes requests across multiple EuroCopilot VMs with least-busy routing and automatic failover.

**Auto-registration**: Standalone VMs can register with a remote LB on boot via `ONEAPP_COPILOT_REGISTER_URL`.

## Configuration

All variables are set via OpenNebula context and re-read on every boot.

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

## Endpoints

| Path | Auth | Description |
|------|------|-------------|
| `/v1/chat/completions` | Bearer token | Chat completions (streaming supported) |
| `/health` | None | Health check |
| `/metrics` | None | Prometheus metrics |
| `/ui` | admin / API key | LiteLLM Web UI (LB mode only) |

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Slow or hanging inference | `CPU_MODEL` must be `host-passthrough`. Check: `grep avx2 /proc/cpuinfo` |
| Service won't start | Needs 32 GB RAM minimum. Check: `journalctl -u eurocopilot` |
| Client TLS error | Self-signed cert by default. Set `ONEAPP_COPILOT_TLS_DOMAIN` or disable verification in client |

## License

Apache 2.0. Model: Devstral Small 2 (Apache 2.0, Mistral AI). Inference: llama.cpp (MIT).
