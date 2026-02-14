---
phase: 01-inference-engine
plan: 02
subsystem: infra
tags: [localai, bash, gguf, systemd, pre-warming, llama-cpp, health-check]

# Dependency graph
requires:
  - phase: 01-01
    provides: "appliance.sh with one-apps lifecycle skeleton and service_install"
provides:
  - "GGUF model download with size verification and resume capability"
  - "Build-time pre-warming cycle (start, inference test, shutdown)"
  - "service_configure with model YAML, env file, and systemd unit generation"
  - "service_bootstrap with systemctl enable+start and /readyz health check"
  - "Helper functions: generate_model_yaml, generate_env_file, generate_systemd_unit, wait_for_localai"
affects: [01-03]

# Tech tracking
tech-stack:
  added: []
  patterns: [idempotent-config-generation, build-time-pre-warming, systemd-health-check, heredoc-overwrite]

key-files:
  created: []
  modified:
    - appliances/slm-copilot/appliance.sh

key-decisions:
  - "Pre-warm uses minimal settings (context_size: 2048, threads: 2) then deletes temp YAML"
  - "daemon-reload in service_configure, not service_bootstrap (configure writes unit, bootstrap starts it)"
  - "OOMScoreAdjust=-500 to protect LocalAI from kernel OOM killer on memory-constrained VMs"
  - "All config heredocs use > overwrite for idempotency on every boot"

patterns-established:
  - "Helper functions in HELPER section below service_help(), following SuperLink pattern"
  - "Build-time pre-warming: start service, test inference, shutdown, cleanup temp config"
  - "Health check loop with configurable timeout (sleep 5, poll /readyz)"
  - "Systemd unit with EnvironmentFile for runtime config separation"

# Metrics
duration: 2min
completed: 2026-02-14
---

# Phase 1 Plan 2: Model Download, Config Generation + Bootstrap Summary

**GGUF model download with build-time pre-warming, idempotent config generation (model YAML + env + systemd), and /readyz health-checked bootstrap**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-14T15:17:17Z
- **Completed:** 2026-02-14T15:19:17Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Extended service_install with 14.3 GB GGUF download (resume-capable) and file size verification
- Implemented full build-time pre-warming cycle: start LocalAI, wait for readyz, test chat completion inference, verify JSON response, clean shutdown
- Implemented service_configure with AVX2 check, model YAML generation (use_jinja: true), environment file, and systemd unit
- Implemented service_bootstrap with systemctl enable+start and 300s /readyz health check
- Created 4 helper functions following SuperLink appliance pattern

## Task Commits

Each task was committed atomically:

1. **Task 1: Add GGUF model download and build-time pre-warming to service_install** - `4f3d39f` (feat)
2. **Task 2: Implement service_configure and service_bootstrap with config generation and health check** - `249fa51` (feat)

## Files Created/Modified
- `appliances/slm-copilot/appliance.sh` - Complete one-apps appliance lifecycle script (329 lines) with all three service stages and 4 helper functions

## Decisions Made
- Pre-warm uses minimal settings (context_size: 2048, threads: 2) to avoid excessive memory during Packer build, then deletes temporary YAML
- Placed daemon-reload in service_configure rather than service_bootstrap (configure writes the unit file, bootstrap starts the service)
- Added OOMScoreAdjust=-500 to systemd unit to protect LocalAI from kernel OOM killer on 32 GB VMs
- All config file generation uses heredoc overwrite (`>`) for idempotency on every boot cycle

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- appliance.sh is ready for plan 01-03 (Nginx reverse proxy, API key auth, Packer template)
- All three lifecycle stages are fully functional: install, configure, bootstrap
- service_configure is idempotent and will regenerate all config from context variables on every boot

## Self-Check: PASSED

- FOUND: appliances/slm-copilot/appliance.sh
- FOUND: 4f3d39f (Task 1 commit)
- FOUND: 249fa51 (Task 2 commit)

---
*Phase: 01-inference-engine*
*Completed: 2026-02-14*
