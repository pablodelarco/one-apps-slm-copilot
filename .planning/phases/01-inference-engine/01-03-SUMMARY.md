---
phase: 01-inference-engine
plan: 03
subsystem: infra
tags: [localai, bash, shellcheck, validation, smoke-test, one-apps]

# Dependency graph
requires:
  - phase: 01-02
    provides: "service_configure with model YAML, env file, systemd unit generation + service_bootstrap"
provides:
  - "validate_config() with CONTEXT_SIZE range validation (512-131072) and THREADS validation"
  - "smoke_test() verifying chat completions, streaming SSE, and /readyz health"
  - "Production-ready appliance.sh passing shellcheck and bash -n with zero warnings"
  - "Complete service_help reference documentation"
  - "All 9 INFER requirements addressed with specific code locations"
affects: [02-nginx-tls, 04-build]

# Tech tracking
tech-stack:
  added: []
  patterns: [fail-fast-validation, smoke-test-helper, shellcheck-compliance]

key-files:
  created: []
  modified:
    - appliances/slm-copilot/appliance.sh

key-decisions:
  - "validate_config placed as first call in service_configure for fail-fast behavior"
  - "smoke_test returns 1 (not exit 1) so callers can handle cleanup before exiting"
  - "SC2034 disabled globally via single directive (all ONE_SERVICE_* vars are framework-consumed)"
  - "Context size range 512-131072: 512 minimum avoids unusable models, 131072 max gets a warning not an error"

patterns-established:
  - "Validation helper pattern: count errors, log each, abort if _errors > 0"
  - "Smoke test pattern: reusable function for both build-time pre-warming and test scripts"
  - "Shellcheck compliance: single SC2034 disable for framework variables, all other warnings fixed inline"

# Metrics
duration: 2min
completed: 2026-02-14
---

# Phase 1 Plan 3: Validation, Smoke Tests + Production Polish Summary

**Context variable validation with fail-fast, reusable smoke test for chat/streaming/health, and shellcheck-clean production script**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-14T15:21:20Z
- **Completed:** 2026-02-14T15:23:50Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Added validate_config() validating CONTEXT_SIZE (positive int, 512-131072 range) and THREADS (non-negative int) with fail-fast abort
- Added smoke_test() helper verifying non-streaming chat completion, streaming SSE, and /readyz health endpoint
- Replaced inline pre-warm curl in service_install with reusable smoke_test call
- Updated service_help with complete reference (all config files, service commands, health check, test curl)
- Achieved shellcheck -s bash zero warnings with single SC2034 global disable
- Verified all 9 INFER requirements addressed with specific code and comments

## Task Commits

Each task was committed atomically:

1. **Task 1: Add context variable validation and smoke test helper** - `3a8c674` (feat)
2. **Task 2: Shellcheck compliance and final polish** - `b5b574a` (chore)

## Files Created/Modified
- `appliances/slm-copilot/appliance.sh` - Production-ready one-apps appliance (414 lines) with 5 lifecycle functions + 6 helpers, all 9 INFER requirements addressed

## Decisions Made
- validate_config placed as first call in service_configure for fail-fast behavior before any config generation
- smoke_test uses return 1 (not exit 1) so callers can handle cleanup (kill pre-warm process) before exiting
- SC2034 disabled globally with single directive since all ONE_SERVICE_* variables are consumed by the one-apps framework
- Context size 131072 gets a warning (not error) since it might work on large VMs despite OOM risk

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- shellcheck was not installed on the build host; installed from GitHub releases to ~/.local/bin (non-blocking, resolved automatically)

## User Setup Required
None - no external service configuration required.

## INFER Requirement Coverage

| Requirement | Description | Code Location |
|-------------|-------------|---------------|
| INFER-01 | /v1/chat/completions | model YAML + smoke_test |
| INFER-02 | Streaming SSE | smoke_test streaming check |
| INFER-03 | Model baked in image | service_install GGUF download |
| INFER-04 | systemd auto-restart | generate_systemd_unit Restart=on-failure |
| INFER-05 | /readyz health | wait_for_localai + smoke_test |
| INFER-06 | Context size config | validate_config + model YAML |
| INFER-07 | Threads config | validate_config + model YAML |
| INFER-08 | Loopback only | systemd --address 127.0.0.1:8080 |
| INFER-09 | Backend pre-downloaded | service_install backends install |

## Next Phase Readiness
- Phase 1 (Inference Engine) is complete: appliance.sh is production-ready
- Ready for Phase 2 to add Nginx reverse proxy, TLS termination, and basic auth
- smoke_test helper can be reused by Phase 4 post-deployment test script (BUILD-03)
- All config generation is idempotent (> overwrite, no >> append patterns)

## Self-Check: PASSED

- FOUND: appliances/slm-copilot/appliance.sh
- FOUND: 01-03-SUMMARY.md
- FOUND: 3a8c674 (Task 1 commit)
- FOUND: b5b574a (Task 2 commit)

---
*Phase: 01-inference-engine*
*Completed: 2026-02-14*
