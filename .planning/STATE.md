# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-13)

**Core value:** One-click deployment of a sovereign, CPU-only AI coding copilot from the OpenNebula marketplace
**Current focus:** Phase 2 complete. Ready for Phase 3 - OpenNebula Integration.

## Current Position

Phase: 2 of 4 (Security & Access) -- COMPLETE
Plan: 2 of 2 in current phase (all done)
Status: Phase 2 complete, ready for Phase 3
Last activity: 2026-02-14 — Completed 02-02 (Let's Encrypt automation with graceful fallback)

Progress: [██████░░░░] 60%

## Performance Metrics

**Velocity:**
- Total plans completed: 5
- Average duration: 2 min
- Total execution time: 0.18 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-inference-engine | 3/3 | 6 min | 2 min |
| 02-security-access | 2/2 | 5 min | 2.5 min |

**Recent Trend:**
- Last 5 plans: 01-01 (2 min), 01-02 (2 min), 01-03 (2 min), 02-01 (3 min), 02-02 (2 min)
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

### Pending Todos

None yet.

### Blockers/Concerns

- RAM footprint with full context window is tight on 32 GB VM (14.3 GB model + KV cache) — default to 32K context, not 128K

## Session Continuity

Last session: 2026-02-14
Stopped at: Completed 02-02-PLAN.md (Let's Encrypt). Phase 2 complete. Ready for Phase 3.
Resume file: None
