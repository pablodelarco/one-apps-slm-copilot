---
phase: 03-opennebula-integration
plan: 01
subsystem: infra
tags: [bash, logging, one-apps, lifecycle, shellcheck]

# Dependency graph
requires:
  - phase: 01-inference-engine
    provides: "appliance.sh with service_install/configure/bootstrap, msg calls throughout"
  - phase: 02-security-access
    provides: "generate_selfsigned_cert, generate_htpasswd, generate_nginx_config, attempt_letsencrypt helpers with msg calls"
provides:
  - "COPILOT_LOG constant (/var/log/one-appliance/slm-copilot.log)"
  - "init_copilot_log() helper for log directory/file creation"
  - "log_copilot() wrapper that writes timestamped entries to dedicated log and passes to one-apps msg"
  - "All lifecycle functions instrumented with log_copilot (zero bare msg calls)"
affects: [03-02, 04-build-pipeline]

# Tech tracking
tech-stack:
  added: []
  patterns: ["log_copilot wrapper pattern: timestamped log file + one-apps msg pass-through"]

key-files:
  created: []
  modified:
    - "appliances/slm-copilot/appliance.sh"

key-decisions:
  - "log_copilot wrapper over msg (not exec/tee redirect) for explicit control without interfering with one-apps pipe mechanism"
  - "init_copilot_log called in all three lifecycle entry points (not just once) for robustness across stage boundaries"
  - "Uppercase log level via ${_level^^} for consistent log file format"

patterns-established:
  - "log_copilot pattern: all new code uses log_copilot instead of msg for dual-output logging"
  - "Lifecycle entry pattern: init_copilot_log + startup marker as first two lines of each lifecycle function"

# Metrics
duration: 4min
completed: 2026-02-14
---

# Phase 3 Plan 01: Dedicated Application Logging Summary

**log_copilot wrapper with timestamped /var/log/one-appliance/slm-copilot.log and zero bare msg calls across 17 functions**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-14T16:30:17Z
- **Completed:** 2026-02-14T16:34:52Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Added COPILOT_LOG constant and two new helper functions (init_copilot_log, log_copilot) for dedicated timestamped logging
- Replaced all 44 msg info/warning/error calls with log_copilot across every lifecycle and helper function
- Each lifecycle function (install, configure, bootstrap) starts with init_copilot_log + startup marker
- Script passes bash -n and shellcheck with zero warnings; 17 total functions confirmed

## Task Commits

Each task was committed atomically:

1. **Task 1: Add log_copilot helper and COPILOT_LOG constant** - `364a2ce` (feat)
2. **Task 2: Replace all msg calls with log_copilot and add init_copilot_log to lifecycle entry points** - `5d9ce83` (feat)

## Files Created/Modified
- `appliances/slm-copilot/appliance.sh` - Added COPILOT_LOG constant, init_copilot_log() and log_copilot() helpers, replaced all msg calls with log_copilot

## Decisions Made
- Used log_copilot wrapper function over exec/tee redirect pattern to avoid interfering with the one-apps framework named pipe + tee logging mechanism
- Call init_copilot_log at the start of all three lifecycle functions (install, configure, bootstrap) rather than once, because each runs in a separate process context
- Used ${_level^^} bash uppercase expansion for consistent log level formatting in the dedicated log file

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Logging infrastructure complete, ready for Plan 03-02 (report file, SSH banner, marketplace metadata)
- All ONE-07 requirements satisfied: dedicated log at /var/log/one-appliance/slm-copilot.log with timestamps
- ONE-01 (context variables), ONE-03 (idempotent configure), ONE-04 (three-stage lifecycle) verified complete from Phases 1-2

## Self-Check: PASSED

- appliances/slm-copilot/appliance.sh: FOUND
- 03-01-SUMMARY.md: FOUND
- Commit 364a2ce (Task 1): FOUND
- Commit 5d9ce83 (Task 2): FOUND

---
*Phase: 03-opennebula-integration*
*Completed: 2026-02-14*
