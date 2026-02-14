---
phase: 01-inference-engine
plan: 01
subsystem: infra
tags: [localai, bash, one-apps, appliance, llama-cpp]

# Dependency graph
requires: []
provides:
  - "appliance.sh with one-apps lifecycle skeleton and service_install"
  - "LocalAI v3.11.0 binary download + llama-cpp backend pre-install"
  - "ONE_SERVICE_PARAMS for CONTEXT_SIZE and THREADS"
  - "Constants for all paths, versions, GGUF URL, UID/GID"
affects: [01-02, 01-03]

# Tech tracking
tech-stack:
  added: [localai-3.11.0, llama-cpp-backend, jq]
  patterns: [one-apps-lifecycle, service-params-array, readonly-constants, idempotent-install]

key-files:
  created:
    - appliances/slm-copilot/appliance.sh
  modified: []

key-decisions:
  - "Followed SuperLink appliance pattern exactly for one-apps conventions"
  - "curl -fSL (no -s) to show download progress during Packer build"
  - "Only jq as runtime dependency -- no Docker, no Nginx in Phase 1"

patterns-established:
  - "ONE_SERVICE_PARAMS 4-element stride: VARNAME, lifecycle_step, description, default"
  - "Default assignments with ${VAR:-default} for context variable fallback"
  - "readonly constants for all paths, versions, and system identifiers"
  - "Idempotent user/group creation with 2>/dev/null || true"

# Metrics
duration: 2min
completed: 2026-02-14
---

# Phase 1 Plan 1: Appliance Skeleton + service_install Summary

**One-apps appliance.sh with LocalAI v3.11.0 binary download, llama-cpp backend pre-install, and localai system user setup**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-14T15:13:31Z
- **Completed:** 2026-02-14T15:15:18Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Created complete one-apps lifecycle skeleton following proven SuperLink pattern
- Implemented service_install with 7-step build-time provisioning sequence
- Defined ONE_SERVICE_PARAMS with CONTEXT_SIZE and THREADS for runtime configuration
- Established constants section with all paths, versions, GGUF URL, and system identifiers

## Task Commits

Each task was committed atomically:

1. **Task 1: Create appliance.sh skeleton with ONE_SERVICE_PARAMS and all lifecycle stubs** - `c7c4822` (feat)
2. **Task 2: Implement service_install with LocalAI binary download, backend pre-install, and directory setup** - `04d426a` (feat)

## Files Created/Modified
- `appliances/slm-copilot/appliance.sh` - One-apps appliance lifecycle script with service_install fully implemented (144 lines)

## Decisions Made
- Followed SuperLink appliance pattern exactly for one-apps conventions (proven pattern, no reinvention)
- Used `curl -fSL` without `-s` flag to show download progress during Packer build (visibility during long builds)
- Only `jq` as runtime dependency for Phase 1 -- Docker, Nginx, and other packages deferred to later phases

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- appliance.sh is ready for plan 01-02 to implement service_bootstrap (model download, systemd unit, model YAML, pre-warming)
- appliance.sh is ready for plan 01-03 to implement service_configure (context variable mapping, model YAML generation)
- All constants needed by future plans are already defined (GGUF URL, model name, paths, etc.)

## Self-Check: PASSED

- FOUND: appliances/slm-copilot/appliance.sh
- FOUND: c7c4822 (Task 1 commit)
- FOUND: 04d426a (Task 2 commit)

---
*Phase: 01-inference-engine*
*Completed: 2026-02-14*
