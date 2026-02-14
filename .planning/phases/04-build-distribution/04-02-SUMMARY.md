---
status: complete
started: 2026-02-14T17:04:00Z
completed: 2026-02-14T17:08:00Z
duration_minutes: 4
---

## What was built

Post-deployment test script (test.sh) that validates a running SLM-Copilot instance with 7 checks: HTTPS connectivity, health endpoint, auth rejection (no credentials → 401), auth acceptance (valid credentials → 200), model listing (devstral-small-2 in response), chat completion (non-streaming with jq parse), and streaming SSE (data: lines in output). Reports [PASS]/[FAIL] for each test with summary count. Exits 0 on all-pass, 1 on any failure.

All bash scripts in the repository pass shellcheck with zero warnings: appliance.sh, build.sh, test.sh, and all three Packer provisioner scripts.

## Key files

### Created
- `test.sh` — Post-deployment test script with 7 validation checks

## Decisions
- curl -sk for all requests (self-signed cert compatibility)
- 120s timeout for chat completion tests (CPU inference is slow)
- Each test independent — failure in one does not skip subsequent tests
- jq for JSON response validation (structured parsing vs grep)

## Requirements
- BUILD-03: Post-deployment test validates HTTPS, auth, health, model, chat, streaming ✓
- BUILD-07: All bash scripts pass shellcheck with zero warnings ✓

## Self-Check: PASSED
- test.sh exists and is executable ✓
- shellcheck passes on all scripts ✓
- 7 report() calls present ✓
- All curl calls use -sk flag ✓
- Chat completion tests use --max-time 120 ✓
