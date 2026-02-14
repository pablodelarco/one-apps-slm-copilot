---
phase: 02-security-access
plan: 01
subsystem: security
tags: [nginx, tls, basic-auth, cors, sse, htpasswd, certbot, openssl, reverse-proxy]

# Dependency graph
requires:
  - phase: 01-inference-engine
    provides: appliance.sh with service_install/configure/bootstrap lifecycle and LocalAI on 127.0.0.1:8080
provides:
  - Nginx reverse proxy with TLS termination (self-signed cert with VM IP SAN)
  - Basic auth with bcrypt htpasswd and auto-generated password
  - CORS headers with always modifier on all add_header directives
  - OPTIONS preflight bypass (204 without auth)
  - SSE streaming proxy with 6 anti-buffering directives + gzip off
  - Health endpoint bypass (/readyz proxied, /health local)
  - HTTP-to-HTTPS redirect with ACME challenge exception
  - Symlink indirection for Let's Encrypt cert swap (plan 02-02)
  - ONEAPP_COPILOT_PASSWORD and ONEAPP_COPILOT_DOMAIN context variables
  - ONEAPP_COPILOT_DOMAIN FQDN validation in validate_config
affects: [02-02-lets-encrypt, 03-marketplace-integration]

# Tech tracking
tech-stack:
  added: [nginx 1.24.x, apache2-utils, certbot, openssl]
  patterns: [single-quoted heredoc for nginx config, symlink cert indirection, constants for config paths]

key-files:
  modified: [appliances/slm-copilot/appliance.sh]

key-decisions:
  - "RSA 2048-bit self-signed certs (ephemeral, regenerated every boot)"
  - "Symlink indirection for cert paths enables Let's Encrypt swap without nginx config changes"
  - "Single-quoted heredoc (<<'NGINX_EOF') prevents bash expansion of nginx variables"
  - "Username always 'copilot' (single-user appliance)"
  - "Password stored in /var/lib/slm-copilot/password for Phase 3 report file"
  - "ssl_buffer_size 4k reduces TLS buffer for better SSE streaming latency"
  - "proxy_read_timeout 600s allows 10-minute CPU inference (3-5 tok/s * 2000 tokens)"
  - "gzip off in location block prevents gzip from buffering SSE output"

patterns-established:
  - "Nginx config generation: single helper function with single-quoted heredoc"
  - "Cert generation before config: certs and htpasswd MUST exist before nginx config references them"
  - "Service ordering: LocalAI ready before nginx starts in service_bootstrap"
  - "Constants for all file paths: NGINX_CONF, NGINX_CERT_DIR, NGINX_HTPASSWD"

# Metrics
duration: 3min
completed: 2026-02-14
---

# Phase 2 Plan 1: Nginx Reverse Proxy Summary

**Nginx reverse proxy with self-signed TLS, bcrypt basic auth, CORS headers, OPTIONS preflight bypass, SSE streaming (7 anti-buffering directives), health endpoint bypass, and HTTP-to-HTTPS redirect**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-14T15:48:13Z
- **Completed:** 2026-02-14T15:52:01Z
- **Tasks:** 6
- **Files modified:** 1

## Accomplishments

- Complete Nginx reverse proxy integrated across all three appliance lifecycle stages (install, configure, bootstrap)
- Self-signed TLS certificate with VM IP SAN and symlink indirection for Let's Encrypt swap
- Basic auth with bcrypt htpasswd, 16-char auto-generated password, and password persistence
- CORS headers with `always` modifier, OPTIONS 204 bypass, SSE streaming with all required anti-buffering directives
- Zero shellcheck warnings, 620 lines, 14 functions, no append patterns

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend service_install with Nginx, apache2-utils, and certbot** - `5b8c316` (feat)
2. **Task 2: Add Phase 2 context variables to ONE_SERVICE_PARAMS** - `d183ede` (feat)
3. **Task 3: Implement generate_selfsigned_cert, generate_htpasswd, generate_nginx_config** - `689e469` (feat)
4. **Task 4: Wire Nginx into service_configure and service_bootstrap** - `f05233d` (feat)
5. **Task 5: Update validate_config with Phase 2 validation** - `5331c60` (feat)
6. **Task 6: Shellcheck compliance and final verification** - no changes needed (all code already compliant)

## Files Created/Modified

- `appliances/slm-copilot/appliance.sh` - Extended from 415 to 620 lines with Nginx reverse proxy, TLS, auth, CORS, SSE streaming, health bypass, HTTP redirect, and 3 new helper functions

## Decisions Made

- RSA 2048-bit for self-signed certs (ephemeral, regenerated every boot -- no need for 4096)
- 3650-day cert expiry to avoid mid-deployment warnings
- Symlink indirection (cert.pem -> selfsigned-cert.pem) so Let's Encrypt can swap by changing symlink target
- Single-quoted heredoc (`<<'NGINX_EOF'`) prevents bash expansion of `$host`, `$request_method`, etc.
- Username always `copilot` (single-user appliance, no user management needed)
- `-B` flag for bcrypt (strongest htpasswd algorithm available)
- `ssl_buffer_size 4k` (reduced from default 16k) for SSE streaming latency
- `proxy_read_timeout 600s` for long CPU inference (default 60s would kill requests)
- `gzip off` in location block prevents gzip from buffering SSE output
- CORS `*` wildcard origin acceptable (basic auth password IS the access control)
- ONEAPP_COPILOT_DOMAIN validation only when non-empty (empty = skip Let's Encrypt)
- `nginx -t` validates config before proceeding; exits on failure

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Self-signed TLS foundation complete with symlink indirection ready for Let's Encrypt swap
- Plan 02-02 will add `attempt_letsencrypt()` to service_bootstrap, reusing the cert.pem/key.pem symlinks
- All ACME infrastructure in place: certbot installed, /var/www/acme-challenge directory created, HTTP server block serves /.well-known/acme-challenge/
- SEC-01 through SEC-05, SEC-08, SEC-09 addressed; SEC-06 and SEC-07 (Let's Encrypt) deferred to plan 02-02

---
*Phase: 02-security-access*
*Completed: 2026-02-14*
