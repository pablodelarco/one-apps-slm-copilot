---
phase: 03-opennebula-integration
plan: 02
subsystem: infra
tags: [bash, one-apps, report-file, ssh-banner, marketplace, yaml, cline, shellcheck]

# Dependency graph
requires:
  - phase: 01-inference-engine
    provides: "appliance.sh with service_install/configure/bootstrap, LocalAI binary and model"
  - phase: 02-security-access
    provides: "generate_selfsigned_cert, generate_htpasswd (persists password to /var/lib/slm-copilot/password), generate_nginx_config, attempt_letsencrypt"
  - phase: 03-opennebula-integration
    plan: 01
    provides: "log_copilot wrapper, init_copilot_log helper, COPILOT_LOG constant"
provides:
  - "write_report_file() helper producing INI-style report at ONE_SERVICE_REPORT with connection info, credentials, model details, service status, Cline config, JSON snippet, curl test"
  - "SSH login banner at /etc/profile.d/slm-copilot-banner.sh with live service status"
  - "marketplace.yaml with European Sovereign AI messaging and complete opennebula_template"
  - "service_help updated with report and log file paths"
affects: [04-build-pipeline]

# Tech tracking
tech-stack:
  added: []
  patterns: ["INI-style report file with defensive ONE_SERVICE_REPORT fallback", "profile.d inline heredoc for dynamic SSH banner"]

key-files:
  created:
    - "appliances/slm-copilot/marketplace.yaml"
  modified:
    - "appliances/slm-copilot/appliance.sh"

key-decisions:
  - "Password always read from /var/lib/slm-copilot/password file, never from ONEAPP_COPILOT_PASSWORD context variable (may be empty for auto-generated)"
  - "Report written in service_bootstrap after services running, not in service_configure (live status fields)"
  - "SSH banner via inline heredoc in service_install (profile.d script), not by appending to /etc/motd (framework-owned)"
  - "Defensive ONE_SERVICE_REPORT fallback: ${ONE_SERVICE_REPORT:-/etc/one-appliance/config}"

patterns-established:
  - "Report file pattern: INI-style sections ([Section Name] + key = value) following WordPress appliance convention"
  - "Profile.d banner pattern: single-quoted heredoc installs static script, script queries live state at login time"

# Metrics
duration: 2min
completed: 2026-02-14
---

# Phase 3 Plan 02: Report File, SSH Banner, and Marketplace Metadata Summary

**INI-style report file with Cline JSON snippet, dynamic SSH login banner, and marketplace YAML with European Sovereign AI messaging**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-14T16:36:59Z
- **Completed:** 2026-02-14T16:39:10Z
- **Tasks:** 2
- **Files modified:** 2 (1 modified, 1 created)

## Accomplishments
- Added write_report_file() helper producing a comprehensive report at ONE_SERVICE_REPORT with connection info, credentials, model details, live service status, Cline VS Code setup instructions, JSON snippet, and curl test command
- Installed SSH login banner to /etc/profile.d/ via inline heredoc that shows live service status, endpoint, and credentials on every SSH login
- Created marketplace.yaml with European Sovereign AI messaging, all 4 ONEAPP_COPILOT_* context variable defaults, and PLACEHOLDER checksums for Phase 4
- Updated service_help with report file and log file paths
- All scripts pass bash -n syntax check and shellcheck with zero warnings

## Task Commits

Each task was committed atomically:

1. **Task 1: Add write_report_file helper, SSH banner, and service_help updates** - `1f51ffc` (feat)
2. **Task 2: Create marketplace metadata YAML with EU sovereign AI messaging** - `367ffe0` (feat)

## Files Created/Modified
- `appliances/slm-copilot/appliance.sh` - Added write_report_file() helper, SSH banner installation in service_install, write_report_file call in service_bootstrap, report/log paths in service_help
- `appliances/slm-copilot/marketplace.yaml` - Community marketplace metadata with European Sovereign AI description, context variable defaults, PLACEHOLDER checksums

## Decisions Made
- Password always read from /var/lib/slm-copilot/password (persisted file), never from $ONEAPP_COPILOT_PASSWORD which may be empty for auto-generated passwords
- Report file written at end of service_bootstrap (after attempt_letsencrypt, before final log) so service status fields reflect actual running state
- SSH banner installed via single-quoted inline heredoc in service_install; the script itself queries live status at login time using systemctl is-active
- Used ${ONE_SERVICE_REPORT:-/etc/one-appliance/config} defensive fallback in case framework variable is not set

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All 8 ONE requirements (ONE-01 through ONE-08) now satisfied across Plans 03-01 and 03-02
- Phase 3 (OpenNebula Integration) is complete
- Ready for Phase 4 (Build Pipeline): Packer definition, build scripts, QCOW2 image, fill PLACEHOLDER checksums in marketplace.yaml
- marketplace.yaml has PLACEHOLDER checksums and PUBLISH_URL that Phase 4 must fill after Packer build

## Self-Check: PASSED

- appliances/slm-copilot/appliance.sh: FOUND
- appliances/slm-copilot/marketplace.yaml: FOUND
- 03-02-SUMMARY.md: FOUND
- Commit 1f51ffc (Task 1): FOUND
- Commit 367ffe0 (Task 2): FOUND

---
*Phase: 03-opennebula-integration*
*Completed: 2026-02-14*
