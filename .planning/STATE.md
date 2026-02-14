# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-13)

**Core value:** One-click deployment of a sovereign, CPU-only AI coding copilot from the OpenNebula marketplace
**Current focus:** Phase 4 complete. All 4 phases done -- project ready for build and marketplace submission.

## Current Position

Phase: 4 of 4 (Build & Distribution) -- COMPLETE
Plan: 3 of 3 in current phase (all plans complete)
Status: All phases complete. Ready for build and marketplace submission.
Last activity: 2026-02-14 -- Completed 04-03 (README documentation, marketplace YAML finalization)

Progress: [██████████] 100%

## Performance Metrics

**Velocity:**
- Total plans completed: 10
- Average duration: 2.4 min
- Total execution time: 0.40 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-inference-engine | 3/3 | 6 min | 2 min |
| 02-security-access | 2/2 | 5 min | 2.5 min |
| 03-opennebula-integration | 2/2 | 6 min | 3 min |
| 04-build-distribution | 3/3 | 7 min | 2.3 min |

**Recent Trend:**
- Last 5 plans: 02-02 (2 min), 03-01 (4 min), 03-02 (2 min), 04-01 (4 min), 04-02 (4 min), 04-03 (2 min)
- Trend: Consistent

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap]: 4-phase structure derived from requirement categories (INFER/SEC/ONE/BUILD) matching component dependency chain
- [Roadmap]: 10 plans total across 4 phases (3/2/2/3 split)
- [01-01]: Followed SuperLink appliance pattern exactly for one-apps conventions
- [01-01]: curl -fSL (no -s) to show download progress during Packer build
- [01-01]: Only jq as runtime dependency for Phase 1
- [01-02]: Pre-warm uses minimal settings (context_size: 2048, threads: 2) then deletes temp YAML
- [01-02]: daemon-reload in service_configure, not service_bootstrap
- [01-02]: OOMScoreAdjust=-500 to protect from OOM killer on 32 GB VMs
- [01-02]: All config heredocs use > overwrite for idempotency
- [01-03]: validate_config placed as first call in service_configure for fail-fast
- [01-03]: smoke_test returns 1 (not exit 1) so callers handle cleanup before exiting
- [01-03]: SC2034 disabled globally for ONE_SERVICE_* framework variables
- [01-03]: Context size 131072 gets warning not error (may work on large VMs)
- [02-01]: RSA 2048-bit self-signed certs (ephemeral, regenerated every boot)
- [02-01]: Symlink indirection for cert paths enables Let's Encrypt swap without config changes
- [02-01]: Single-quoted heredoc (<<'NGINX_EOF') prevents bash expansion of nginx variables
- [02-01]: ssl_buffer_size 4k for SSE streaming latency; proxy_read_timeout 600s for CPU inference
- [02-01]: gzip off in location block prevents gzip from buffering SSE output
- [02-01]: CORS wildcard origin acceptable (basic auth password IS the access control)
- [02-01]: ONEAPP_COPILOT_DOMAIN validation only when non-empty (empty = skip Let's Encrypt)
- [02-02]: certbot --webroot mode (nginx stays running, serves ACME challenge on port 80)
- [02-02]: --register-unsafely-without-email (ephemeral VMs, no email needed)
- [02-02]: Let's Encrypt failure is a WARNING, never an error (service always works with self-signed)
- [02-02]: Deploy hook in /etc/letsencrypt/renewal-hooks/deploy/ for automatic nginx reload on renewal
- [03-01]: log_copilot wrapper over msg (not exec/tee redirect) to avoid interfering with one-apps pipe mechanism
- [03-01]: init_copilot_log called in all three lifecycle entry points for robustness across stage boundaries
- [03-01]: Uppercase log level via ${_level^^} for consistent log file format
- [03-02]: Password always read from /var/lib/slm-copilot/password file, never from ONEAPP_COPILOT_PASSWORD context variable
- [03-02]: Report written in service_bootstrap after services running (not service_configure) for live status
- [03-02]: SSH banner via profile.d inline heredoc (framework owns /etc/motd)
- [03-02]: Defensive ONE_SERVICE_REPORT fallback: ${ONE_SERVICE_REPORT:-/etc/one-appliance/config}
- [04-01]: Packer VM resources: 4 vCPU / 16 GB RAM / 50 GB disk (model download + pre-warm needs)
- [04-01]: SSH timeout 30m to accommodate 14 GB model download during service_install
- [04-01]: build.sh auto-clones one-apps if not present (simplest for new users)
- [04-02]: curl -sk for all test requests (self-signed cert compatibility)
- [04-02]: 120s timeout for chat completion tests (CPU inference is slow)
- [04-03]: README structured as 14-section developer onboarding document
- [04-03]: Manual build guide documents 12 steps replicating Packer 8-step sequence
- [04-03]: Marketplace YAML keeps PLACEHOLDER values with instruction comments for post-build replacement

### Pending Todos

None.

### Blockers/Concerns

- RAM footprint with full context window is tight on 32 GB VM (14.3 GB model + KV cache) — default to 32K context, not 128K

## Session Continuity

Last session: 2026-02-14
Stopped at: Completed 04-03-PLAN.md (README documentation, marketplace YAML finalization). Phase 04 complete. All 10 plans across 4 phases executed. Project ready for build and marketplace submission.
Resume file: None
