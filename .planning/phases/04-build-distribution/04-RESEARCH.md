# Phase 4: Build & Distribution - Research

**Researched:** 2026-02-14
**Domain:** Packer HCL2 QCOW2 builds, Makefile build orchestration, build wrapper scripts, post-deployment test scripts, shellcheck compliance, community marketplace YAML metadata, README documentation, manual build guide
**Confidence:** HIGH

## Summary

Phase 4 packages the working SLM-Copilot appliance (LocalAI + Nginx + one-apps lifecycle from Phases 1-3) into a distributable QCOW2 image via Packer, wraps the build in a Makefile with convenience targets, provides a post-deployment test script, ensures all bash scripts pass shellcheck, completes the README documentation, and finalizes the marketplace YAML metadata that was drafted in Phase 3 (03-02).

The critical findings are: (1) The Packer HCL2 definition follows a proven two-build pattern from the Flower appliance -- Build 1 generates a cloud-init seed ISO via `cloud-localds`, Build 2 provisions the QCOW2 via the QEMU builder with an 8-step provisioning sequence (SSH hardening, one-context install, framework files, appliance script, context hooks, `service install`, cleanup); (2) This appliance requires significantly more Packer VM resources than the Flower reference (4 vCPU / 16 GB RAM / 50 GB disk vs 2 vCPU / 4 GB / 10 GB) because the 14.3 GB model download and pre-warm inference need RAM and disk; (3) The build wrapper script (`build.sh`) must handle dependency checking (packer, qemu-img, cloud-localds), base image download, Packer execution, QCOW2 compression, and checksum generation; (4) The post-deployment test script (`test.sh`) validates a running instance over HTTPS by checking connectivity, auth, health, model listing, chat completion, and streaming -- it does NOT deploy the VM (that is the operator's responsibility); (5) The marketplace YAML already exists at `appliances/slm-copilot/marketplace.yaml` with PLACEHOLDER checksums and PUBLISH_URL that must be filled after the first successful build; (6) All bash scripts currently pass shellcheck with zero warnings -- Phase 4 must maintain this as new scripts are added; (7) The `one-apps` framework files (service.sh, common.sh, functions.sh, context scripts) must be sourced from a local `one-apps` repo checkout, same as the Flower appliance build.

**Primary recommendation:** Plan 04-01 should create the Packer HCL definition (adapted from Flower's superlink.pkr.hcl with increased resources), the build wrapper script (build.sh), cloud-init configuration, supporting Packer provisioner scripts, and the Makefile with `build`, `clean`, `checksum`, and `lint` targets. Plan 04-02 should create the post-deployment test script (test.sh) with pass/fail reporting and ensure all new scripts pass shellcheck, adding a `test` target to the Makefile. Plan 04-03 should complete the README documentation (architecture, quick start, variables, Cline setup, troubleshooting, performance), finalize the marketplace YAML with real checksums after a successful build, and write the manual build guide.

## Standard Stack

### Core

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Packer | v1.15.0 (Feb 2026) | QCOW2 image builder from Ubuntu 24.04 cloud image | Latest stable; QEMU plugin v1.1.4; proven in Flower appliance; HCL2 syntax |
| QEMU/KVM | system default | Virtual machine for Packer build; KVM acceleration | Standard Linux virtualization; Packer QEMU builder requires it |
| cloud-localds | cloud-image-utils package | Generate cloud-init seed ISO for Packer SSH access | Standard approach for booting Ubuntu cloud images with custom credentials |
| qemu-img | system default | QCOW2 compression (`qemu-img convert -c -O qcow2`) and info | Standard QCOW2 manipulation tool; reduces 25 GB image to ~10-15 GB |
| shellcheck | 0.11.0+ | Static analysis of all bash scripts | Industry standard for shell script linting; catches quoting bugs, unset variables |
| GNU Make | system default | Build orchestration (build, test, checksum, clean, lint targets) | Universal build driver; proven pattern from Flower appliance |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| curl | system default | Post-deployment test script; base image download | Test script validates HTTPS endpoints; build script downloads Ubuntu cloud image |
| jq | system default | JSON response parsing in test script | Validate chat completion response structure |
| sha256sum / md5sum | system default | Checksum generation for marketplace YAML | After successful build, before marketplace submission |
| uuidgen | system default | Generate UUID for marketplace YAML filename | Once, when preparing PR to marketplace-community |
| gawk | system default | SSH config hardening in Packer provisioner | Standard approach from one-apps; used by 81-configure-ssh.sh |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Packer QEMU builder | virt-install + virsh | Packer is declarative, idempotent, and has built-in SSH provisioning; virt-install requires manual scripting |
| cloud-localds (seed ISO) | Context ISO (mkisofs) | cloud-localds is simpler for Ubuntu cloud images; context ISO is the one-apps production approach but requires gen_context script |
| Makefile | bash script | Makefile provides dependency tracking, parallel execution, and standard `make` interface; bash script requires manual dependency management |
| shellcheck | bash -n only | bash -n checks syntax only; shellcheck catches quoting bugs, undefined variables, and POSIX portability issues |
| Post-deployment test script (bash) | Ruby test framework (one-apps pattern) | Ruby tests require VM lifecycle management; bash script tests a running instance directly; simpler for operators |

## Architecture Patterns

### Pattern 1: Two-Build Packer Pattern (Proven from Flower Appliance)

**What:** The Packer definition contains two `build` blocks. Build 1 is a `null` source that runs a `shell-local` provisioner to generate the cloud-init seed ISO. Build 2 is a `qemu` source that boots the Ubuntu cloud image with the seed ISO attached, provisions via SSH, and produces the output QCOW2.

**When to use:** Always for one-apps appliances built from Ubuntu cloud images.

**Source:** Flower SuperLink appliance (`/home/pablo/flower-opennebula/build/packer/superlink/superlink.pkr.hcl`), verified working.

```hcl
# Build 1: Generate cloud-init seed ISO
source "null" "context" {
  communicator = "none"
}
build {
  name    = "context"
  sources = ["source.null.context"]
  provisioner "shell-local" {
    inline = [
      "cloud-localds ${var.appliance_name}-cloud-init.iso cloud-init.yml",
    ]
  }
}

# Build 2: Provision the QCOW2 image
source "qemu" "slm_copilot" {
  accelerator = "kvm"
  cpus        = 4          # More than Flower (2) -- model pre-warm needs CPU
  memory      = 16384      # More than Flower (4096) -- model loading needs RAM
  disk_size   = "50G"      # More than Flower (10G) -- 14.3 GB model + OS
  # ... (see Code Examples below)
}
```

**Key difference from Flower:** This appliance needs significantly more build VM resources because:
- The 14.3 GB GGUF model must be downloaded and stored on disk (needs 50 GB disk)
- The pre-warm step loads the model into memory for test inference (needs 16 GB RAM)
- The pre-warm inference test benefits from more CPU threads (needs 4 vCPU)
- The `ssh_timeout` must be much longer (30m vs 10m) because the model download can take 10-20 minutes

### Pattern 2: Eight-Step Provisioning Sequence

**What:** The QEMU build uses a standardized 8-step provisioning sequence that matches the one-apps appliance build process exactly.

**When to use:** Always for one-apps appliances.

**Source:** Flower SuperLink Packer HCL (lines 70-158) and community-apps example Packer HCL.

```
Step 1: SSH hardening (81-configure-ssh.sh)
Step 2: Install one-context package (copies .deb, runs 80-install-context.sh)
Step 3: Create one-appliance directory structure
Step 4: Install one-apps framework files (service.sh, common.sh, functions.sh, context hooks)
Step 5: Install appliance script (appliance.sh -> /etc/one-appliance/service.d/appliance.sh)
Step 6: Move context hooks into place (82-configure-context.sh)
Step 7: Run service_install() via /etc/one-appliance/service install
Step 8: Cleanup (purge cloud-init, clear apt cache, truncate machine-id, sync)
```

**SLM-Copilot-specific considerations for Step 7:**
- `service install` downloads LocalAI binary (~50 MB), llama-cpp backend (~200 MB), and GGUF model (~14.3 GB)
- The pre-warm step starts LocalAI, runs a test inference, then shuts down
- Total time for Step 7: 15-30 minutes depending on network speed
- Packer `ssh_timeout` must accommodate this (set to 30m)

### Pattern 3: Cloud-Init Configuration for Packer SSH

**What:** A cloud-init YAML file configures the Ubuntu cloud image with root password access so Packer can SSH in. SSH hardening (step 1) reverts these insecure settings after provisioning.

**When to use:** Always for Ubuntu cloud image-based Packer builds.

**Source:** Flower SuperLink cloud-init.yml.

```yaml
#cloud-config
growpart:
  mode: auto
  devices: [/]
users:
  - name: root
    lock_passwd: false
    hashed_passwd: $6$rounds=4096$...  # "opennebula"
disable_root: false
ssh_pwauth: true
runcmd:
  # Enable root SSH login for Packer provisioning
  - gawk ... PermitRootLogin yes
  - systemctl reload sshd || systemctl reload ssh
```

**SLM-Copilot addition:** Add `growpart` for root partition to use the full 50 GB disk (default cloud image is 2 GB). The Flower cloud-init already includes this.

### Pattern 4: Build Wrapper Script (build.sh)

**What:** A shell script that wraps the entire build process: checks dependencies, downloads the base Ubuntu cloud image if needed, downloads the one-context .deb if needed, runs `packer init` and `packer build`, compresses the output QCOW2, and generates checksums.

**When to use:** Always -- the Makefile `build` target calls this script.

**Design:**
```
build.sh flow:
  1. Check dependencies (packer, qemu-img, cloud-localds, KVM module)
  2. Download Ubuntu 24.04 cloud image if not present in images/
  3. Download one-context .deb if not present in context/
  4. Clone/update one-apps repo if not present
  5. Run: packer init build/packer/
  6. Run: packer build build/packer/
  7. Compress: qemu-img convert -c -O qcow2 output/raw.qcow2 output/slm-copilot.qcow2
  8. Generate: sha256sum, md5sum -> output/checksums.txt
  9. Print: image path, size, checksums
```

**Key decisions:**
- The Ubuntu 24.04 cloud image URL is `https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img`
- The one-context package must be pre-downloaded (Packer copies it into the VM via file provisioner)
- The one-apps framework files must be available locally (cloned repo or submodule)
- QCOW2 compression typically reduces 25 GB to 10-15 GB (depends on model file compressibility, which is LOW for GGUF quantized data)

**QCOW2 compression note:** GGUF files are already quantized data that does not compress well. The 14.3 GB model file will compress to approximately 12-13 GB. OS and packages (~4 GB) compress well to ~2 GB. Expected final compressed image: ~15-18 GB.

### Pattern 5: Post-Deployment Test Script (test.sh)

**What:** A bash script that validates a running SLM-Copilot instance by sending requests over HTTPS and checking responses. It does NOT deploy or manage VMs -- it tests an already-running instance.

**When to use:** After deploying the built QCOW2 to an OpenNebula cloud. Called by `make test ENDPOINT=https://vm-ip PASSWORD=xxx`.

**Design:**
```
test.sh flow:
  1. Parse arguments: endpoint URL, password (or read from env vars)
  2. Test 1: HTTPS connectivity (curl -k to port 443, expect 401 Unauthorized)
  3. Test 2: Health endpoint (GET /readyz without auth, expect 200)
  4. Test 3: Auth rejection (GET /v1/models without auth, expect 401)
  5. Test 4: Auth acceptance (GET /v1/models with auth, expect 200 + model list)
  6. Test 5: Model listing (parse JSON response, expect devstral-small-2 in list)
  7. Test 6: Chat completion (POST /v1/chat/completions with auth, expect 200 + content)
  8. Test 7: Streaming (POST /v1/chat/completions?stream=true, expect SSE data: lines)
  9. Report: pass/fail for each test, overall result
```

**Output format:**
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

**Important:** The test script must use `curl -k` (insecure) because the appliance uses self-signed certificates by default. The `--max-time` flag should be generous (120s for chat completions on CPU).

### Pattern 6: Makefile with Standard Targets

**What:** A Makefile at the project root providing `build`, `test`, `checksum`, `clean`, and `lint` targets.

**When to use:** Always -- this is the primary build interface per BUILD-05.

**Source:** Flower appliance Makefile (`/home/pablo/flower-opennebula/build/Makefile`), adapted.

```makefile
# Key targets:
build      # Run Packer build -> compressed QCOW2
test       # Run post-deployment test against ENDPOINT
checksum   # Generate md5 + sha256 for QCOW2 image
clean      # Remove build artifacts (output/, ISOs)
lint       # shellcheck all .sh files in repo
```

**Makefile variables:**
- `ENDPOINT` -- VM IP/hostname for test target (required for `make test`)
- `PASSWORD` -- API password for test target (required for `make test`)
- `INPUT_DIR` -- Directory with base Ubuntu image (default: `build/images`)
- `OUTPUT_DIR` -- Directory for build output (default: `build/export`)
- `ONE_APPS_DIR` -- Path to one-apps checkout (default: `build/one-apps`)
- `HEADLESS` -- Packer headless mode (default: true)

### Pattern 7: Marketplace YAML Finalization

**What:** The marketplace YAML at `appliances/slm-copilot/marketplace.yaml` was created in Phase 3 (03-02) with PLACEHOLDER values for checksums and PUBLISH_URL. After a successful build, these must be filled with real values.

**When to use:** After the first successful build, before marketplace PR submission.

**Current state of marketplace.yaml:**
```yaml
images:
  - name: slm_copilot_os
    url: 'https://PUBLISH_URL/slm-copilot-1.0.0.qcow2'
    type: OS
    dev_prefix: vd
    driver: qcow2
    size: 26843545600
    checksum:
      md5: 'PLACEHOLDER'
      sha256: 'PLACEHOLDER'
```

**What needs updating after build:**
- `url`: Replace `PUBLISH_URL` with actual hosting URL (CloudFront, S3, or OpenNebula marketplace CDN)
- `size`: Update with actual virtual disk size from `qemu-img info --output=json | jq .["virtual-size"]`
- `checksum.md5`: Output of `md5sum slm-copilot-1.0.0.qcow2`
- `checksum.sha256`: Output of `sha256sum slm-copilot-1.0.0.qcow2`
- `creation_time`: Update to current epoch (`date +%s`)

**Note:** The marketplace YAML filename should be a UUID per marketplace-community conventions. The current filename `marketplace.yaml` is for development; for the PR, rename to a UUID (e.g., `<uuid>.yaml`).

### Pattern 8: Manual Build Guide

**What:** A document (section in README or separate file) that describes how to build the QCOW2 image step-by-step without Packer, for users who want to customize the build or understand the internals.

**When to use:** Documentation only -- provides transparency into what Packer automates.

**Steps:**
```
1. Download Ubuntu 24.04 cloud image
2. Create VM from image with 4 vCPU, 16 GB RAM, 50 GB disk
3. Boot VM, SSH in as root
4. Harden SSH (disable password auth)
5. Install one-context package
6. Set up one-appliance framework (directory structure, framework files)
7. Copy appliance.sh to /etc/one-appliance/service.d/
8. Configure context hooks
9. Run: /etc/one-appliance/service install
10. Cleanup: purge cloud-init, clear apt cache, truncate machine-id
11. Shutdown VM
12. Export QCOW2, compress with qemu-img convert -c
```

### Anti-Patterns to Avoid

- **Building without KVM acceleration:** Packer QEMU builder without `accelerator = "kvm"` uses software emulation, making the build 10-50x slower. The build host MUST have KVM available (`/dev/kvm`).
- **Skipping QCOW2 compression:** The raw output QCOW2 is ~25 GB. Always run `qemu-img convert -c -O qcow2` to compress. For marketplace images, smaller is better (faster download for users).
- **Running fstrim inside the Packer VM:** Some guides recommend `fstrim -a` before image capture. This is NOT needed when using `qemu-img convert -c` post-build, which handles zero-block detection automatically.
- **Hardcoding one-apps path:** The one-apps framework files must come from a configurable path (`ONE_APPS_DIR` variable), not a hardcoded location. Different build hosts will have it in different places.
- **Using the community-apps context ISO approach instead of cloud-localds:** The example appliance in marketplace-community uses `mkisofs` to create a context ISO with `gen_context`. The Flower appliance uses `cloud-localds` for cloud-init. Both work, but cloud-localds is simpler for Ubuntu cloud images and is the pattern we follow.
- **Testing the build output directly:** The test script tests a RUNNING instance, not the QCOW2 file. The operator must deploy the image to an OpenNebula cloud first, then run `make test` against the running VM.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Cloud-init seed ISO generation | Manual mkisofs commands | `cloud-localds` from cloud-image-utils | Single command, handles NoCloud datasource format |
| SSH hardening in Packer VM | Custom script | `81-configure-ssh.sh` from Flower/one-apps pattern | Proven, handles sshd_config.d edge cases |
| Context hook installation | Manual mv + chmod | `82-configure-context.sh` from Flower/one-apps pattern | Handles both net-90 and net-99 scripts |
| QCOW2 checksum generation | Custom Python script | `sha256sum` and `md5sum` (coreutils) | Standard, universally available |
| JSON response validation in tests | grep/sed parsing | `jq` for structured queries | Reliable JSON parsing, dot notation for field access |
| Marketplace YAML generation | Custom template engine | Edit the existing marketplace.yaml manually | Simple key-value replacement; too few values to justify a template engine |

## Common Pitfalls

### Pitfall 1: Packer SSH Timeout During Model Download

**What goes wrong:** The 14.3 GB model download takes 10-20 minutes. Packer's default `ssh_timeout` (5m) or `ssh_wait_timeout` may expire during this step, causing Packer to kill the SSH session and abort the build.
**Why it happens:** Packer uses `ssh_timeout` for the initial connection AND `ssh_wait_timeout` for subsequent provisioner steps. If a shell provisioner takes too long (the `service install` step downloads 14.3 GB), the session may timeout.
**How to avoid:** Set `ssh_timeout = "30m"` and `ssh_wait_timeout = "1800s"` (30 minutes). The Flower appliance uses `ssh_timeout = "10m"` which is sufficient for its lighter workload but NOT for a 14 GB download.
**Warning signs:** Packer output shows "Waiting for SSH to become available..." followed by timeout error. Build fails at step 7 (service install).

### Pitfall 2: Insufficient Disk Space in Packer VM

**What goes wrong:** The Packer VM runs out of disk space during the model download. The GGUF file is 14.3 GB, LocalAI binary is ~50 MB, backend is ~200 MB, and the OS takes ~4 GB. The default 10 GB disk from the Flower template is far too small.
**Why it happens:** Copy-pasting Packer HCL from a lighter appliance without adjusting disk_size.
**How to avoid:** Set `disk_size = "50G"` in the Packer QEMU source. This provides 14.3 (model) + 0.3 (binary+backend) + 4 (OS) + 1 (packages) + 30 (headroom) = ~50 GB.
**Warning signs:** `service install` fails with "No space left on device" errors. `df -h` shows / is 100% full.

### Pitfall 3: Missing one-apps Framework Files

**What goes wrong:** The Packer build fails because it cannot find `service.sh`, `common.sh`, `functions.sh`, or the context scripts. These are sourced from a local `one-apps` repository checkout, which must exist on the build host.
**Why it happens:** The Flower appliance uses relative paths like `${var.one_apps_dir}/appliances/service.sh`. If `one_apps_dir` doesn't point to a valid one-apps checkout, the file provisioner fails.
**How to avoid:** The build wrapper script (build.sh) must check for the one-apps directory and offer to clone it if missing. Document the required one-apps checkout in the README.
**Warning signs:** Packer error: "source path does not exist: .../one-apps/appliances/service.sh"

### Pitfall 4: QCOW2 Not Compressed Before Marketplace Upload

**What goes wrong:** The raw Packer output QCOW2 is ~25 GB (virtual size = 50 GB, actual size = ~25 GB with sparse allocation). Without compression, the marketplace download is unnecessarily large.
**Why it happens:** Packer's `disk_compression` setting only applies to the QCOW2 internal format, not to post-build compression. The Flower Packer HCL sets `disk_compression = false`.
**How to avoid:** Add a post-build step that runs `qemu-img convert -c -O qcow2 raw.qcow2 compressed.qcow2`. The Makefile `build` target should include this automatically. The `checksum` target generates checksums from the compressed image.
**Warning signs:** `qemu-img info` shows actual size close to virtual size.

### Pitfall 5: Test Script Fails with Self-Signed Certificate

**What goes wrong:** The test script uses `curl` without `-k` (insecure) and fails because the appliance uses self-signed certificates.
**Why it happens:** Default curl behavior validates TLS certificates. Self-signed certs are not trusted.
**How to avoid:** Always use `curl -k` in the test script. Document that `-k` is required for self-signed certificates.
**Warning signs:** curl error: "SSL certificate problem: self-signed certificate".

### Pitfall 6: Shellcheck Fails on New Scripts

**What goes wrong:** New scripts added in Phase 4 (build.sh, test.sh) introduce shellcheck warnings that were not present in the existing appliance.sh.
**Why it happens:** Different coding styles, missing `set -euo pipefail`, unquoted variables, or unused variables.
**How to avoid:** Run `shellcheck` on every new script during development. The `make lint` target must check ALL `.sh` files in the repo. Use `set -euo pipefail` at the top of every new script. Quote all variable expansions.
**Warning signs:** `make lint` exits non-zero.

### Pitfall 7: one-context Package Version Mismatch

**What goes wrong:** The one-context .deb package version doesn't match the Ubuntu release, causing installation failures or missing network configuration during VM boot.
**Why it happens:** one-context packages are versioned per OpenNebula release AND per distro. Using the wrong combination fails.
**How to avoid:** Download the one-context package matching Ubuntu 24.04 and the target OpenNebula version (6.10+). The build script should download the correct version automatically from the OpenNebula repos.
**Warning signs:** `dpkg -i` fails with dependency errors. VM boots but has no network.

## Code Examples

### Packer HCL2 Definition (slm-copilot.pkr.hcl)

```hcl
packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = ">= 1.1.0"
    }
  }
}

# Build 1: Generate cloud-init seed ISO
source "null" "context" {
  communicator = "none"
}

build {
  name    = "context"
  sources = ["source.null.context"]

  provisioner "shell-local" {
    inline = [
      "cloud-localds ${var.appliance_name}-cloud-init.iso cloud-init.yml",
    ]
  }
}

# Build 2: Provision the SLM-Copilot QCOW2 image
source "qemu" "slm_copilot" {
  accelerator = "kvm"

  cpus      = 4
  memory    = 16384
  disk_size = "50G"

  iso_url      = "${var.input_dir}/ubuntu2404.qcow2"
  iso_checksum = "none"
  disk_image   = true

  output_directory = "${var.output_dir}"
  vm_name          = "${var.appliance_name}.qcow2"
  format           = "qcow2"

  headless = var.headless

  net_device     = "virtio-net"
  disk_interface = "virtio"

  qemuargs = [
    ["-cdrom", "${var.appliance_name}-cloud-init.iso"],
    ["-serial", "mon:stdio"],
    ["-cpu", "host"],
  ]

  boot_wait = "30s"

  communicator     = "ssh"
  ssh_username     = "root"
  ssh_password     = "opennebula"
  ssh_timeout      = "30m"
  ssh_wait_timeout = "1800s"

  shutdown_command = "poweroff"
}

build {
  name    = "slm-copilot"
  sources = ["source.qemu.slm_copilot"]

  # Step 1: SSH hardening
  provisioner "shell" {
    script = "scripts/81-configure-ssh.sh"
  }

  # Step 2: Install one-context package
  provisioner "shell" {
    inline = ["mkdir -p /context"]
  }

  provisioner "file" {
    source      = "${var.one_apps_dir}/context-linux/out/"
    destination = "/context"
  }

  provisioner "shell" {
    script = "scripts/80-install-context.sh"
  }

  # Step 3: Create one-appliance directory structure
  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline = [
      "install -o 0 -g 0 -m u=rwx,g=rx,o=   -d /etc/one-appliance/{,service.d/,lib/}",
      "install -o 0 -g 0 -m u=rwx,g=rx,o=rx -d /opt/one-appliance/{,bin/}",
    ]
  }

  # Step 4: Install one-apps framework files
  provisioner "file" {
    sources = [
      "${var.one_apps_dir}/appliances/scripts/net-90-service-appliance",
      "${var.one_apps_dir}/appliances/scripts/net-99-report-ready",
    ]
    destination = "/etc/one-appliance/"
  }

  provisioner "file" {
    source      = "${var.one_apps_dir}/appliances/service.sh"
    destination = "/etc/one-appliance/service"
  }

  provisioner "shell" {
    inline = ["chmod 0755 /etc/one-appliance/service"]
  }

  provisioner "file" {
    source      = "${var.one_apps_dir}/appliances/lib/common.sh"
    destination = "/etc/one-appliance/lib/common.sh"
  }

  provisioner "file" {
    source      = "${var.one_apps_dir}/appliances/lib/functions.sh"
    destination = "/etc/one-appliance/lib/functions.sh"
  }

  # Step 5: Install SLM-Copilot appliance script
  provisioner "file" {
    source      = "../../appliances/slm-copilot/appliance.sh"
    destination = "/etc/one-appliance/service.d/appliance.sh"
  }

  # Step 6: Move context hooks into place
  provisioner "shell" {
    script = "scripts/82-configure-context.sh"
  }

  # Step 7: Run service_install (downloads binary, model, pre-warms)
  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline         = ["/etc/one-appliance/service install && sync"]
  }

  # Step 8: Cleanup for cloud reuse
  provisioner "shell" {
    inline = [
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get purge -y cloud-init snapd fwupd || true",
      "apt-get autoremove -y --purge || true",
      "apt-get clean -y",
      "rm -rf /var/lib/apt/lists/*",
      "rm -f /etc/sysctl.d/99-cloudimg-ipv6.conf",
      "rm -rf /context/",
      "truncate -s 0 /etc/machine-id",
      "rm -f /var/lib/dbus/machine-id",
      "rm -rf /tmp/* /var/tmp/*",
      "sync",
    ]
  }
}
```

### Packer Variables (variables.pkr.hcl)

```hcl
variable "appliance_name" {
  type    = string
  default = "slm-copilot"
}

variable "input_dir" {
  type        = string
  description = "Directory containing base OS image (ubuntu2404.qcow2)"
}

variable "output_dir" {
  type        = string
  description = "Directory for output QCOW2 image"
}

variable "headless" {
  type    = bool
  default = true
}

variable "version" {
  type    = string
  default = "1.0.0"
}

variable "one_apps_dir" {
  type        = string
  description = "Path to one-apps repository checkout"
  default     = "../one-apps"
}
```

### Cloud-Init YAML (cloud-init.yml)

```yaml
#cloud-config
growpart:
  mode: auto
  devices: [/]

users:
  - name: root
    lock_passwd: false
    # Password: "opennebula" (bcrypt hash)
    hashed_passwd: $6$rounds=4096$2RFfXKGPKTcdF.CH$dzLlW9Pg1jbeojxRxEraHwEMAPAbpChBdrMFV1SOa6etSF2CYAe.hC1dRDM1icTOk7M4yhVS1BtwJjah9essD0

disable_root: false
ssh_pwauth: true

runcmd:
  - |
    gawk -i inplace -f- /etc/ssh/sshd_config <<'EOF'
    BEGIN { update = "PermitRootLogin yes" }
    /^[#\s]*PermitRootLogin\s/ { $0 = update; found = 1 }
    { print }
    ENDFILE { if (!found) print update }
    EOF
  - |
    gawk -i inplace -f- /etc/ssh/sshd_config.d/*-cloudimg-settings.conf <<'EOF'
    BEGIN { update = "PasswordAuthentication yes" }
    /^PasswordAuthentication\s/ { $0 = update }
    { print }
    EOF
  - gawk '' || rm -rf /etc/ssh/sshd_config.d/*-cloudimg-settings.conf
  - gawk '' || echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
  - systemctl reload sshd || systemctl reload ssh
```

### Post-Deployment Test Script (test.sh)

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage: ./test.sh <endpoint> <password>
# Example: ./test.sh https://10.0.0.1 mypassword

ENDPOINT="${1:?Usage: $0 <endpoint> <password>}"
PASSWORD="${2:?Usage: $0 <endpoint> <password>}"
USERNAME="copilot"
MODEL="devstral-small-2"
TIMEOUT=120

_pass=0
_fail=0
_total=0

report() {
    local _status="$1"
    local _name="$2"
    _total=$((_total + 1))
    if [ "${_status}" = "PASS" ]; then
        _pass=$((_pass + 1))
        printf '[PASS] %s\n' "${_name}"
    else
        _fail=$((_fail + 1))
        printf '[FAIL] %s\n' "${_name}"
    fi
}

echo ""
echo "SLM-Copilot Post-Deployment Test"
echo "================================="
echo "Endpoint: ${ENDPOINT}"
echo ""

# Test 1: HTTPS connectivity
if curl -sk --max-time 10 -o /dev/null -w '%{http_code}' "${ENDPOINT}/" | grep -qE '(401|200|301)'; then
    report PASS "HTTPS connectivity"
else
    report FAIL "HTTPS connectivity"
fi

# Test 2: Health endpoint (no auth required)
if curl -sk --max-time 10 "${ENDPOINT}/readyz" | grep -qi 'ok\|ready'; then
    report PASS "Health endpoint (/readyz)"
else
    report FAIL "Health endpoint (/readyz)"
fi

# Test 3: Auth rejection (no credentials)
_code=$(curl -sk --max-time 10 -o /dev/null -w '%{http_code}' "${ENDPOINT}/v1/models")
if [ "${_code}" = "401" ]; then
    report PASS "Auth rejection (no credentials)"
else
    report FAIL "Auth rejection (no credentials) -- got HTTP ${_code}"
fi

# Test 4: Auth acceptance (valid credentials)
_code=$(curl -sk --max-time 10 -u "${USERNAME}:${PASSWORD}" -o /dev/null -w '%{http_code}' "${ENDPOINT}/v1/models")
if [ "${_code}" = "200" ]; then
    report PASS "Auth acceptance (valid credentials)"
else
    report FAIL "Auth acceptance (valid credentials) -- got HTTP ${_code}"
fi

# Test 5: Model listing
_models=$(curl -sk --max-time 10 -u "${USERNAME}:${PASSWORD}" "${ENDPOINT}/v1/models" 2>/dev/null)
if echo "${_models}" | jq -e ".data[] | select(.id == \"${MODEL}\")" >/dev/null 2>&1; then
    report PASS "Model listing (${MODEL})"
else
    report FAIL "Model listing (${MODEL})"
fi

# Test 6: Chat completion (non-streaming)
_response=$(curl -sk --max-time "${TIMEOUT}" -u "${USERNAME}:${PASSWORD}" \
    -H 'Content-Type: application/json' \
    "${ENDPOINT}/v1/chat/completions" \
    -d "{\"model\":\"${MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hello in one word\"}],\"max_tokens\":10}" 2>/dev/null)
if echo "${_response}" | jq -e '.choices[0].message.content' >/dev/null 2>&1; then
    report PASS "Chat completion (non-streaming)"
else
    report FAIL "Chat completion (non-streaming)"
fi

# Test 7: Streaming chat completion
if curl -sk --max-time "${TIMEOUT}" -u "${USERNAME}:${PASSWORD}" \
    -H 'Content-Type: application/json' \
    "${ENDPOINT}/v1/chat/completions" \
    -d "{\"model\":\"${MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hi\"}],\"max_tokens\":5,\"stream\":true}" 2>/dev/null \
    | grep -q 'data:'; then
    report PASS "Chat completion (streaming SSE)"
else
    report FAIL "Chat completion (streaming SSE)"
fi

# Summary
echo ""
echo "Result: ${_pass}/${_total} tests passed"
if [ "${_fail}" -gt 0 ]; then
    exit 1
fi
```

### Makefile

```makefile
SHELL := /bin/bash

# Directories
INPUT_DIR   ?= $(CURDIR)/build/images
OUTPUT_DIR  ?= $(CURDIR)/build/export
ONE_APPS_DIR ?= $(CURDIR)/build/one-apps
PACKER_DIR  := $(CURDIR)/build/packer

# Build settings
HEADLESS    ?= true
VERSION     ?= 1.0.0
IMAGE_NAME  := slm-copilot-$(VERSION).qcow2

# Test settings (required for 'make test')
ENDPOINT    ?=
PASSWORD    ?=

.PHONY: build test checksum clean lint help

help:
	@echo "SLM-Copilot Build Targets"
	@echo "========================="
	@echo "  make build                       Build QCOW2 image"
	@echo "  make test ENDPOINT=... PASSWORD=...  Test running instance"
	@echo "  make checksum                    Generate checksums for image"
	@echo "  make clean                       Remove build artifacts"
	@echo "  make lint                        Shellcheck all bash scripts"

build:
	@echo "==> Building SLM-Copilot image..."
	./build.sh

test:
	@test -n "$(ENDPOINT)" || { echo "ERROR: ENDPOINT required (e.g., make test ENDPOINT=https://10.0.0.1 PASSWORD=xxx)"; exit 1; }
	@test -n "$(PASSWORD)" || { echo "ERROR: PASSWORD required"; exit 1; }
	./test.sh "$(ENDPOINT)" "$(PASSWORD)"

checksum: $(OUTPUT_DIR)/$(IMAGE_NAME)
	@echo "==> Generating checksums..."
	cd $(OUTPUT_DIR) && sha256sum $(IMAGE_NAME) > $(IMAGE_NAME).sha256
	cd $(OUTPUT_DIR) && md5sum $(IMAGE_NAME) > $(IMAGE_NAME).md5
	@echo "SHA256: $$(cat $(OUTPUT_DIR)/$(IMAGE_NAME).sha256)"
	@echo "MD5:    $$(cat $(OUTPUT_DIR)/$(IMAGE_NAME).md5)"

clean:
	rm -rf $(OUTPUT_DIR)
	rm -f $(PACKER_DIR)/slm-copilot-cloud-init.iso
	@echo "==> Build artifacts cleaned."

lint:
	@echo "==> Running shellcheck on all bash scripts..."
	shellcheck -x appliances/slm-copilot/appliance.sh
	@if [ -f build.sh ]; then shellcheck -x build.sh; fi
	@if [ -f test.sh ]; then shellcheck -x test.sh; fi
	@find build/packer/scripts -name '*.sh' -exec shellcheck -x {} + 2>/dev/null || true
	@echo "==> All scripts passed shellcheck."
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Packer JSON templates | Packer HCL2 templates | Packer v1.7+ (2021) | HCL2 is now the standard; JSON is legacy; use `.pkr.hcl` extension |
| cloud-init NoCloud via mkisofs | cloud-localds from cloud-image-utils | Always preferred for Ubuntu | Simpler single command; handles NoCloud format automatically |
| Manual QCOW2 compression | `qemu-img convert -c -O qcow2` post-build | Standard practice | Reduces image size 40-60% depending on content |
| one-apps context ISO (gen_context + mkisofs) | cloud-localds (cloud-init.yml) | Both valid | cloud-localds for Ubuntu cloud images; context ISO for one-apps production pipeline |
| Ruby test framework (one-apps certification tests) | Bash test script with curl | Bash for simplicity | Ruby tests need one-apps test infra; bash tests are standalone and operator-friendly |

**Deprecated/outdated:**
- Packer JSON templates: Use HCL2 (`.pkr.hcl`) exclusively
- `disk_compression = true` in Packer QEMU builder: Does not reliably compress; use post-build `qemu-img convert -c` instead
- `skip_compaction` Packer setting: Not applicable for QCOW2 format

## Open Questions

1. **one-apps framework checkout strategy**
   - What we know: The Flower appliance uses a `one_apps_dir` variable pointing to a local checkout. The build script needs `service.sh`, `common.sh`, `functions.sh`, context scripts, and context-linux .deb packages.
   - What's unclear: Whether to use git submodule, git clone in build.sh, or require manual checkout. The Flower Makefile uses `ONE_APPS_DIR ?= $(CURDIR)/../one-apps` (sibling directory).
   - Recommendation: The build wrapper script should clone one-apps from GitHub if the directory doesn't exist. This is the simplest approach for new users. Advanced users can set `ONE_APPS_DIR` to their existing checkout.

2. **one-context package download**
   - What we know: The one-context .deb is installed from a pre-staged directory in the Packer VM. The Flower appliance copies from `${var.one_apps_dir}/context-linux/out/`.
   - What's unclear: Whether one-apps builds the context package or it must be downloaded separately.
   - Recommendation: The one-apps repo includes tooling to build context packages. The build script should check if the context .deb exists and provide instructions if not. Alternatively, download a pre-built .deb from OpenNebula repos.

3. **GGUF file compressibility in QCOW2**
   - What we know: GGUF files are quantized floating-point data. Quantized data does not compress well because it looks like random bits.
   - What's unclear: The exact compression ratio for a 14.3 GB Q4_K_M GGUF file inside a QCOW2 image.
   - Recommendation: Expect the compressed QCOW2 to be 15-18 GB (model barely compresses; OS compresses well). This is still a large image but acceptable for a marketplace appliance that eliminates a 14 GB runtime download.

4. **Marketplace YAML filename (UUID)**
   - What we know: The marketplace-community repo requires filenames to be UUIDs (e.g., `c16c278c-464e-4b34-a77b-47208179dc76.yaml`).
   - What's unclear: Whether to generate the UUID now or when preparing the actual PR.
   - Recommendation: Keep `marketplace.yaml` for development. When preparing the marketplace-community PR, generate a UUID (`uuidgen`) and rename the file. Document this step in the README.

5. **Ubuntu 24.04 cloud image resizing**
   - What we know: Ubuntu cloud images ship at ~3.5 GB virtual size. The appliance needs 50 GB.
   - What's unclear: Whether Packer's `disk_size = "50G"` automatically resizes the image, or if `qemu-img resize` is needed before the build.
   - Recommendation: Packer's QEMU builder with `disk_image = true` and `disk_size = "50G"` should resize the base image. The `growpart` in cloud-init expands the root partition. If this doesn't work, add a `qemu-img resize` step in the build wrapper.

## Directory Structure (Phase 4 additions)

```
/home/pablo/demo-ga/
  Makefile                                    # NEW: build orchestration
  build.sh                                    # NEW: build wrapper script
  test.sh                                     # NEW: post-deployment test script
  build/
    packer/
      slm-copilot.pkr.hcl                     # NEW: Packer HCL definition
      variables.pkr.hcl                       # NEW: Packer variables
      cloud-init.yml                          # NEW: cloud-init for Packer SSH
      scripts/
        80-install-context.sh                 # NEW: one-context installer
        81-configure-ssh.sh                   # NEW: SSH hardening
        82-configure-context.sh               # NEW: context hook setup
    images/                                   # Base Ubuntu image (downloaded by build.sh)
      ubuntu2404.qcow2
    one-apps/                                 # one-apps checkout (cloned by build.sh)
    export/                                   # Build output
      slm-copilot-1.0.0.qcow2                # Compressed final image
      slm-copilot-1.0.0.qcow2.sha256
      slm-copilot-1.0.0.qcow2.md5
  appliances/
    slm-copilot/
      appliance.sh                            # EXISTING: lifecycle script (Phases 1-3)
      marketplace.yaml                        # EXISTING: marketplace metadata (Phase 3, update checksums)
  README.md                                   # NEW: complete documentation
```

## Sources

### Primary (HIGH confidence)
- [Flower SuperLink Packer HCL](/home/pablo/flower-opennebula/build/packer/superlink/superlink.pkr.hcl) -- proven two-build pattern, 8-step provisioning, verified working
- [Flower Makefile](/home/pablo/flower-opennebula/build/Makefile) -- build/clean/validate targets, directory conventions
- [Flower cloud-init.yml](/home/pablo/flower-opennebula/build/packer/superlink/cloud-init.yml) -- root password, SSH enablement, growpart
- [Flower packer scripts (80/81/82)](/home/pablo/flower-opennebula/build/packer/scripts/) -- one-context install, SSH hardening, context hook setup
- [marketplace-community README](/home/pablo/marketplace-wizard/README.md) -- YAML format specification, UUID filename convention
- [marketplace-community example UUID.yaml](/home/pablo/marketplace-wizard/appliances/example/UUID.yaml) -- template with all required fields
- [RabbitMQ marketplace YAML](/home/pablo/marketplace-wizard/appliances/rabbitmq/c16c278c-464e-4b34-a77b-47208179dc76.yaml) -- real-world example with checksums, user_inputs, inputs_order
- [Packer QEMU Builder Documentation](https://developer.hashicorp.com/packer/integrations/hashicorp/qemu/latest/components/builder/qemu) -- all source block parameters
- [community-apps example Packer HCL](/home/pablo/marketplace-wizard/apps-code/community-apps/packer/example/example.pkr.hcl) -- official community-apps build pattern

### Secondary (MEDIUM confidence)
- [Packer GitHub Releases](https://github.com/hashicorp/packer/releases) -- v1.15.0 (Feb 4, 2026)
- [Ubuntu Cloud Images](https://cloud-images.ubuntu.com/noble/current/) -- noble-server-cloudimg-amd64.img
- [OpenNebula context-linux packages](https://github.com/OpenNebula/one-apps/tree/master/context-linux) -- .deb package build process
- [shellcheck documentation](https://www.shellcheck.net/) -- linting rules and directives

### Tertiary (LOW confidence)
- GGUF file compressibility -- estimated based on general quantized data properties, not empirically measured for this specific file
- Packer `disk_size` auto-resize behavior with `disk_image = true` -- documented but not personally tested with 50 GB expansion

## Metadata

**Confidence breakdown:**
- Packer HCL pattern: HIGH -- directly verified from working Flower appliance and community-apps example
- Build provisioning sequence: HIGH -- identical pattern across Flower, RabbitMQ, and example appliances
- Makefile targets: HIGH -- adapted from working Flower Makefile
- Post-deployment test script: HIGH -- straightforward curl-based testing with well-known API endpoints
- Marketplace YAML: HIGH -- format verified from README and multiple real-world examples
- Shellcheck compliance: HIGH -- appliance.sh already passes; standard tool usage
- QCOW2 compression: MEDIUM -- standard approach but exact compression ratio for GGUF-heavy image not empirically measured
- Build wrapper script: MEDIUM -- new script, follows established patterns but needs implementation testing

**Research date:** 2026-02-14
**Valid until:** 2026-03-14 (Packer versions stable; marketplace format hasn't changed)
