---
status: complete
started: 2026-02-14T17:04:00Z
completed: 2026-02-14T17:08:00Z
duration_minutes: 4
---

## What was built

Complete Packer build pipeline for the SLM-Copilot QCOW2 image. The two-build pattern generates a cloud-init seed ISO (Build 1) then provisions Ubuntu 24.04 via QEMU with an 8-step sequence (Build 2): SSH hardening, one-context install, one-apps framework, appliance script, context hooks, service_install, and cleanup. VM sized for the 14.3 GB model: 4 vCPU, 16 GB RAM, 50 GB disk, 30m SSH timeout.

build.sh wraps the full lifecycle: dependency checking (packer, qemu-img, cloud-localds, /dev/kvm), Ubuntu cloud image download, one-apps clone, packer init+build, QCOW2 compression, and checksum generation. Makefile provides build, test, checksum, clean, lint, and help targets.

## Key files

### Created
- `build/packer/slm-copilot.pkr.hcl` — Two-build Packer definition
- `build/packer/variables.pkr.hcl` — Packer variables (appliance_name, input_dir, output_dir, headless, version, one_apps_dir)
- `build/packer/cloud-init.yml` — Cloud-init for Packer SSH access with growpart
- `build/packer/scripts/80-install-context.sh` — one-context .deb installer
- `build/packer/scripts/81-configure-ssh.sh` — SSH hardening (reverts build-time settings)
- `build/packer/scripts/82-configure-context.sh` — Context hook setup
- `build.sh` — Build wrapper script
- `Makefile` — Build orchestration with 6 targets

## Decisions
- Packer VM resources: 4 vCPU / 16 GB RAM / 50 GB disk (model download + pre-warm needs)
- SSH timeout 30m to accommodate 14 GB model download during service_install
- build.sh auto-clones one-apps if not present (simplest for new users)
- Provisioner scripts sourced directly from Flower appliance (proven pattern)

## Requirements
- BUILD-01: Packer HCL2 builds compressed QCOW2 from Ubuntu 24.04 ✓
- BUILD-05: Makefile with build/test/checksum/clean/lint targets ✓
- BUILD-06: Build wrapper script with dependency checking ✓

## Self-Check: PASSED
- All 8 files exist ✓
- shellcheck passes on all scripts ✓
- Packer HCL has QEMU source, 50G disk, 30m timeout, cloud-localds, service install ✓
- make help runs without error ✓
