# SLM-Copilot: Sovereign AI Coding Assistant for OpenNebula

One-click deployment of a sovereign, CPU-only AI coding copilot from the OpenNebula marketplace.

## Overview

SLM-Copilot is an OpenNebula marketplace appliance that deploys a fully sovereign AI coding assistant on any standard VM -- no GPU required. It packages [Devstral Small 2](https://mistral.ai/products/devstral) (24B parameters, Q4\_K\_M quantization) served by [LocalAI](https://localai.io/) behind an Nginx reverse proxy with TLS encryption and basic authentication.

The key value proposition is sovereignty and simplicity: your code stays in your jurisdiction, your data never leaves your infrastructure, and you get a working AI coding copilot in minutes without any cloud API subscriptions or GPU hardware. Import the appliance from the OpenNebula marketplace, instantiate a VM with 32 GB RAM and 16 vCPUs, and connect from VS Code with the [Cline](https://cline.bot) extension.

The entire stack is 100% open-source, built by European companies: Apache 2.0 for the Devstral model (Mistral AI, Paris), MIT for LocalAI inference engine, BSD for Nginx reverse proxy, and Apache 2.0 for OpenNebula (Madrid) cloud platform and the one-apps appliance framework.

## Architecture

```
Developer Machine            OpenNebula VM (32 GB RAM, 16 vCPU)
+------------------+         +------------------------------------------+
| VS Code + Cline  |  HTTPS  | Nginx (TLS + Basic Auth + CORS)  :443   |
|  OpenAI Provider |-------->|   |                                      |
+------------------+         |   v                                      |
                             | LocalAI (llama-cpp backend)     :8080    |
                             |   |                                      |
                             |   v                                      |
                             | Devstral Small 2 (24B Q4_K_M, ~14 GB)   |
                             +------------------------------------------+
```

**Data flow:** Cline sends OpenAI-compatible API requests over HTTPS to port 443. Nginx terminates TLS (self-signed or Let's Encrypt), validates basic auth credentials, adds CORS headers, and proxies requests to LocalAI on localhost:8080. LocalAI loads the Devstral Small 2 GGUF model via the llama-cpp backend and returns chat completions (streaming or non-streaming). All inference runs on CPU using the VM's available cores.

**Components:**

- **Nginx** -- Reverse proxy handling TLS termination, HTTP basic authentication, CORS headers for browser-based clients, and SSE streaming passthrough. Listens on ports 80 (HTTPS redirect + ACME challenge) and 443 (API).
- **LocalAI** -- OpenAI-compatible inference server running the llama-cpp backend. Binds to 127.0.0.1:8080 (not exposed externally). Managed by systemd with OOM protection.
- **Devstral Small 2** -- 24B parameter coding model by Mistral AI, quantized to Q4\_K\_M (~14 GB). Optimized for code analysis, refactoring, test generation, and bug fixes. Requires Jinja2 chat template support (enabled via `use_jinja: true`).

## Quick Start

### Prerequisites

- OpenNebula 6.10+ with KVM hypervisor
- VM template: 32 GB RAM, 16 vCPU, 50 GB disk (minimum)
- Network: port 443 open (and port 80 if using Let's Encrypt)

### Steps

1. **Import** the appliance from the OpenNebula marketplace (or build from source with `make build`)
2. **Create a VM** from the template, optionally setting `ONEAPP_*` context variables (see [Configuration](#configuration-oneapp_-variables))
3. **Wait for boot** -- service startup takes approximately 2 minutes (model loading into memory)
4. **Check connection details** by SSHing into the VM:
   ```bash
   cat /etc/one-appliance/config
   ```
   This shows the endpoint URL, password, model info, and Cline configuration.
5. **Connect from VS Code** using the Cline extension (see [Cline Setup](#cline-setup-vs-code))
6. **Validate** the deployment:
   ```bash
   make test ENDPOINT=https://<vm-ip> PASSWORD=<password>
   ```

## Configuration (ONEAPP\_\* Variables)

All configuration is done via OpenNebula context variables, set when creating or updating the VM template.

| Variable | Default | Description |
|----------|---------|-------------|
| `ONEAPP_COPILOT_PASSWORD` | *(auto-generated)* | API password for basic auth. If empty, a random 16-character password is generated on first boot. Username is always `copilot`. |
| `ONEAPP_COPILOT_DOMAIN` | *(empty)* | FQDN for Let's Encrypt certificate. If empty, a self-signed certificate is generated using the VM's IP address. |
| `ONEAPP_COPILOT_CONTEXT_SIZE` | `32768` | Token context window size (valid range: 512--131072). Larger values use more RAM for the KV cache. |
| `ONEAPP_COPILOT_THREADS` | `0` *(auto-detect)* | CPU threads for inference. `0` means auto-detect all available cores. Set to the number of physical cores for best performance. |

**Context size and RAM:** The 24B Q4\_K\_M model uses approximately 14 GB of RAM. The remaining memory is used by the KV cache, which scales with context size. On a 32 GB VM, the default 32K context window leaves adequate headroom. Setting context size to 128K on a 32 GB VM may trigger the OOM killer -- use 64 GB RAM or higher for large context windows.

All variables are re-read on every VM boot (the appliance is fully reconfigurable). Change a value in the VM template and reboot to apply.

## Cline Setup (VS Code)

[Cline](https://cline.bot) is an AI coding assistant extension for VS Code that supports OpenAI-compatible API providers.

### Step-by-step

1. Install the **Cline** extension in VS Code (search for "Cline" in the Extensions marketplace)
2. Open the Cline panel and click the **settings gear icon**
3. Select **"OpenAI Compatible"** as the API Provider
4. Enter the connection details from your VM's report file (`cat /etc/one-appliance/config`):
   - **Base URL:** `https://<vm-ip>/v1`
   - **API Key:** `<password>`
   - **Model ID:** `devstral-small-2`

### JSON configuration snippet

For direct settings.json editing, add:

```json
{
  "cline.apiProvider": "openai-compatible",
  "cline.openAiCompatible.apiUrl": "https://<vm-ip>",
  "cline.openAiCompatible.apiKey": "<password>",
  "cline.openAiCompatible.modelId": "devstral-small-2"
}
```

Replace `<vm-ip>` with the VM's IP address (or domain if `ONEAPP_COPILOT_DOMAIN` is set) and `<password>` with the API password from the report file.

### Notes on self-signed certificates

If using the default self-signed certificate (no `ONEAPP_COPILOT_DOMAIN` set), the Cline extension should work without issues as it typically does not verify TLS certificates for custom endpoints. If you encounter connection errors, the report file on the VM (`cat /etc/one-appliance/config`) provides the exact configuration values and a curl test command for debugging.

## Building from Source

### Prerequisites

- [Packer](https://www.packer.io/) v1.15+
- QEMU/KVM with `/dev/kvm` accessible
- `cloud-localds` (from the `cloud-image-utils` package)
- `qemu-img` (from the `qemu-utils` package)
- ~50 GB free disk space
- Internet access (downloads Ubuntu cloud image, one-apps framework, LocalAI binary, and the 14 GB model)

### Build

```bash
git clone <repo-url>
cd demo-ga
make build
```

### Build process

The build wrapper (`build.sh`) orchestrates the following:

1. Checks for required dependencies (packer, qemu-img, cloud-localds, /dev/kvm)
2. Downloads the Ubuntu 24.04 cloud image if not already present
3. Clones the [one-apps](https://github.com/OpenNebula/one-apps) framework if not already present
4. Runs `packer init` and `packer build` (two-build pattern: cloud-init ISO generation + QEMU provisioning)
5. The Packer QEMU build provisions the image with an 8-step sequence: SSH hardening, one-context install, one-apps framework, appliance script, context hooks, `service install` (downloads LocalAI + model + pre-warms), and cleanup
6. Compresses the output QCOW2 with `qemu-img convert -c`
7. Generates SHA256 and MD5 checksums

### Build output

- Image: `build/export/slm-copilot-1.0.0.qcow2` (~15-18 GB compressed)
- Checksums: `build/export/slm-copilot-1.0.0.qcow2.sha256` and `.md5`

### Build time

20-40 minutes depending on network speed (14 GB model download) and CPU speed (model pre-warm inference test).

### Makefile targets

| Target | Description |
|--------|-------------|
| `make build` | Build the QCOW2 image (full pipeline) |
| `make test ENDPOINT=... PASSWORD=...` | Run post-deployment tests against a running instance |
| `make checksum` | Regenerate checksums for the built image |
| `make clean` | Remove build artifacts (build/export/, cloud-init ISO) |
| `make lint` | Run shellcheck on all bash scripts in the repository |
| `make help` | Show available targets |

## Manual Build Guide (without Packer)

For users who want to understand the build internals or customize the image without Packer, follow these steps manually. This replicates what the Packer build automates.

### Prerequisites

- A hypervisor capable of running Ubuntu 24.04 VMs (KVM, VirtualBox, etc.)
- The Ubuntu 24.04 cloud image or server ISO
- SSH access to the VM as root
- Internet access from the VM

### Steps

**1. Download the Ubuntu 24.04 cloud image**

```bash
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
```

Alternatively, install Ubuntu 24.04 Server from an ISO.

**2. Create a VM with adequate resources**

- 4 vCPU, 16 GB RAM, 50 GB disk (minimum for build)
- The production VM needs 32 GB RAM and 16 vCPU; the build VM needs less because it only pre-warms briefly

**3. Boot the VM and SSH in as root**

```bash
ssh root@<vm-ip>
```

**4. Harden SSH (disable password authentication)**

```bash
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl reload ssh
```

**5. Install the one-context package**

Download the latest one-context `.deb` for Ubuntu from the [OpenNebula one-apps releases](https://github.com/OpenNebula/one-apps/releases) and install:

```bash
dpkg -i one-context*.deb
apt-get install -f -y
```

**6. Create the one-appliance directory structure**

```bash
install -o 0 -g 0 -m u=rwx,g=rx,o=   -d /etc/one-appliance/{,service.d/,lib/}
install -o 0 -g 0 -m u=rwx,g=rx,o=rx -d /opt/one-appliance/{,bin/}
```

**7. Install the one-apps framework files**

Clone the [one-apps repository](https://github.com/OpenNebula/one-apps) and copy the framework files:

```bash
git clone --depth 1 https://github.com/OpenNebula/one-apps.git /tmp/one-apps

cp /tmp/one-apps/appliances/service.sh /etc/one-appliance/service
chmod 0755 /etc/one-appliance/service

cp /tmp/one-apps/appliances/lib/common.sh /etc/one-appliance/lib/
cp /tmp/one-apps/appliances/lib/functions.sh /etc/one-appliance/lib/

cp /tmp/one-apps/appliances/scripts/net-90-service-appliance /etc/one-appliance/
cp /tmp/one-apps/appliances/scripts/net-99-report-ready /etc/one-appliance/
```

**8. Copy the appliance script**

```bash
cp appliances/slm-copilot/appliance.sh /etc/one-appliance/service.d/appliance.sh
```

**9. Configure context hooks**

Move the network-triggered scripts into the context hook directories so the one-apps lifecycle runs on every boot:

```bash
mv /etc/one-appliance/net-90-service-appliance /etc/one-context.d/net.d/
mv /etc/one-appliance/net-99-report-ready /etc/one-context.d/net.d/
chmod 0755 /etc/one-context.d/net.d/net-90-service-appliance
chmod 0755 /etc/one-context.d/net.d/net-99-report-ready
```

**10. Run service install**

This is the longest step -- it downloads LocalAI (~50 MB), the llama-cpp backend (~200 MB), and the Devstral model (~14 GB), then pre-warms the model with a test inference.

```bash
/etc/one-appliance/service install
```

Expected time: 15-30 minutes depending on network speed.

**11. Cleanup for cloud reuse**

```bash
export DEBIAN_FRONTEND=noninteractive
apt-get purge -y cloud-init snapd fwupd || true
apt-get autoremove -y --purge || true
apt-get clean -y
rm -rf /var/lib/apt/lists/*
rm -f /etc/sysctl.d/99-cloudimg-ipv6.conf
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
rm -rf /tmp/* /var/tmp/*
sync
```

**12. Shutdown, export, and compress**

```bash
poweroff
```

From the host, export and compress the disk image:

```bash
qemu-img convert -c -O qcow2 /path/to/vm-disk.qcow2 slm-copilot-1.0.0.qcow2
sha256sum slm-copilot-1.0.0.qcow2 > slm-copilot-1.0.0.qcow2.sha256
md5sum slm-copilot-1.0.0.qcow2 > slm-copilot-1.0.0.qcow2.md5
```

The resulting `slm-copilot-1.0.0.qcow2` can be imported into OpenNebula as a marketplace image.

## Testing

After deploying the appliance to a VM, validate the instance:

```bash
make test ENDPOINT=https://<vm-ip> PASSWORD=<password>
```

The test script (`test.sh`) runs 7 checks:

| # | Test | What it validates |
|---|------|-------------------|
| 1 | HTTPS connectivity | Port 443 responds (any HTTP status) |
| 2 | Health endpoint | `/readyz` returns OK (no auth required) |
| 3 | Auth rejection | Request without credentials returns 401 |
| 4 | Auth acceptance | Request with valid credentials returns 200 |
| 5 | Model listing | `/v1/models` contains `devstral-small-2` |
| 6 | Chat completion | Non-streaming `/v1/chat/completions` returns valid JSON |
| 7 | Streaming SSE | Streaming request returns `data:` lines |

Expected output:

```
SLM-Copilot Post-Deployment Test
=================================
Endpoint: https://10.0.0.1

[PASS] HTTPS connectivity
[PASS] Health endpoint (/readyz)
[PASS] Auth rejection (no credentials)
[PASS] Auth acceptance (valid credentials)
[PASS] Model listing (devstral-small-2)
[PASS] Chat completion (non-streaming)
[PASS] Chat completion (streaming SSE)

Result: 7/7 tests passed
```

All requests use `curl -sk` (self-signed certificate compatibility). Chat completion tests use a 120-second timeout to accommodate CPU inference speeds.

## Troubleshooting

### Service not starting after boot

```bash
systemctl status local-ai
journalctl -u local-ai -f
```

Check that the VM has at least 32 GB RAM. The model requires ~14 GB just for loading, plus KV cache overhead.

### Slow inference

CPU inference with a 24B model is expected to be 5-15 tokens/second depending on hardware. To improve speed:

- Increase the number of vCPUs assigned to the VM
- Reduce context size (`ONEAPP_COPILOT_CONTEXT_SIZE`) to lower KV cache memory pressure
- Ensure the CPU supports AVX2 (check `grep avx2 /proc/cpuinfo`); AVX-512 provides further improvement
- Set `ONEAPP_COPILOT_THREADS` to the number of physical cores (auto-detect may overcount with hyperthreading)

### Let's Encrypt failed

This is a warning, not an error -- the appliance falls back to self-signed certificates automatically. Check:

- DNS resolves `ONEAPP_COPILOT_DOMAIN` to the VM's public IP
- Port 80 is reachable from the internet (ACME HTTP-01 challenge)
- The domain is correct (no typos, includes subdomain if applicable)

### Out of memory

The 24B Q4\_K\_M model needs approximately 14 GB of RAM. The KV cache scales with context window size. On a 32 GB VM:

- 32K context (default): ~14 GB model + ~2 GB KV cache = ~16 GB total (safe)
- 128K context: ~14 GB model + ~8 GB KV cache = ~22 GB total (tight)

Reduce `ONEAPP_COPILOT_CONTEXT_SIZE` if the OOM killer terminates LocalAI.

### Cline cannot connect

1. Verify HTTPS is working: `curl -k https://<vm-ip>/readyz`
2. Check the password: SSH into the VM and run `cat /etc/one-appliance/config`
3. Verify firewall allows port 443
4. Ensure the API URL in Cline includes `/v1` (e.g., `https://<vm-ip>/v1`)
5. Check Cline logs in VS Code: Output panel > select "Cline" from the dropdown

### Log locations

| Log | Location |
|-----|----------|
| Application log | `/var/log/one-appliance/slm-copilot.log` |
| LocalAI service | `journalctl -u local-ai` |
| Nginx access/error | `journalctl -u nginx` |
| Report file | `/etc/one-appliance/config` |

## Performance

Expected inference performance with Devstral Small 2 (24B Q4\_K\_M):

| vCPUs | RAM | Context Size | Approx. Speed |
|-------|-----|--------------|---------------|
| 8 | 32 GB | 32K | ~3-5 tok/s |
| 16 | 32 GB | 32K | ~5-10 tok/s |
| 32 | 64 GB | 64K | ~10-15 tok/s |

**Notes:**

- Speeds are approximate and depend on CPU architecture, memory bandwidth, and prompt complexity
- AVX-512 support significantly improves inference speed (20-40% over AVX2-only CPUs)
- Context size affects memory usage -- larger context windows require more RAM for the KV cache
- First request after boot is slower due to model loading and initial memory allocation
- The model is pre-warmed during image build, so cold-start on deployment is just memory mapping (~30-60 seconds)

## Marketplace Submission

To submit the built image to the OpenNebula marketplace-community repository:

1. **Build the image** and generate checksums:
   ```bash
   make build
   make checksum
   ```
2. **Upload the QCOW2** to a public hosting location (CDN, S3, or similar)
3. **Update `appliances/slm-copilot/marketplace.yaml`** with the actual URL and checksums from `build/export/`
4. **Rename the YAML** to a UUID for the marketplace PR:
   ```bash
   cp appliances/slm-copilot/marketplace.yaml "$(uuidgen).yaml"
   ```
5. **Submit a PR** to the [marketplace-community](https://github.com/OpenNebula/marketplace-community) repository with the UUID-named YAML file

## License

The SLM-Copilot appliance is licensed under the Apache License 2.0.

**Component licenses:**

| Component | License | Maintainer |
|-----------|---------|------------|
| Devstral Small 2 | Apache 2.0 | Mistral AI (Paris) |
| LocalAI | MIT | Ettore Di Giacinto |
| Nginx | BSD-2-Clause | Nginx Inc. |
| OpenNebula one-apps | Apache 2.0 | OpenNebula Systems (Madrid) |

## Author

Pablo del Arco, Cloud-Edge Innovation Engineer at [OpenNebula Systems](https://opennebula.io/).
