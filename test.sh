#!/usr/bin/env bash
set -euo pipefail

# SLM-Copilot Post-Deployment Test
# Validates a running instance with 7 checks.
# Usage: ./test.sh <endpoint> <password>
# Example: ./test.sh https://10.0.0.1:8443 myapikey

ENDPOINT="${1:?Usage: $0 <endpoint> <password>}"
PASSWORD="${2:?Usage: $0 <endpoint> <password>}"
MODEL="devstral-small-2"
TIMEOUT=120

_pass=0
_fail=0
_total=0

report() {
    local _status="$1"
    local _name="$2"
    _total=$((_total + 1))
    if [ "${_status}" = "PASS" ]; then
        _pass=$((_pass + 1))
        printf '[PASS] %s\n' "${_name}"
    else
        _fail=$((_fail + 1))
        printf '[FAIL] %s\n' "${_name}"
    fi
}

echo ""
echo "SLM-Copilot Post-Deployment Test"
echo "================================="
echo "Endpoint: ${ENDPOINT}"
echo ""

# Test 1: HTTPS connectivity
if curl -sk --max-time 10 -o /dev/null -w '%{http_code}' "${ENDPOINT}/" | grep -qE '(401|200|301)'; then
    report PASS "HTTPS connectivity"
else
    report FAIL "HTTPS connectivity"
fi

# Test 2: Health endpoint (no auth required)
if curl -sk --max-time 10 "${ENDPOINT}/health" | grep -qi 'ok\|status'; then
    report PASS "Health endpoint (/health)"
else
    report FAIL "Health endpoint (/health)"
fi

# Test 3: Auth rejection (no credentials)
_code=$(curl -sk --max-time 10 -o /dev/null -w '%{http_code}' "${ENDPOINT}/v1/models")
if [ "${_code}" = "401" ]; then
    report PASS "Auth rejection (no credentials)"
else
    report FAIL "Auth rejection (no credentials) -- got HTTP ${_code}"
fi

# Test 4: Auth acceptance (valid Bearer token)
_code=$(curl -sk --max-time 10 -H "Authorization: Bearer ${PASSWORD}" -o /dev/null -w '%{http_code}' "${ENDPOINT}/v1/models")
if [ "${_code}" = "200" ]; then
    report PASS "Auth acceptance (valid Bearer token)"
else
    report FAIL "Auth acceptance (valid Bearer token) -- got HTTP ${_code}"
fi

# Test 5: Model listing
_models=$(curl -sk --max-time 10 -H "Authorization: Bearer ${PASSWORD}" "${ENDPOINT}/v1/models" 2>/dev/null)
if echo "${_models}" | jq -e ".data[] | select(.id == \"${MODEL}\")" >/dev/null 2>&1; then
    report PASS "Model listing (${MODEL})"
else
    report FAIL "Model listing (${MODEL})"
fi

# Test 6: Chat completion (non-streaming)
_response=$(curl -sk --max-time "${TIMEOUT}" -H "Authorization: Bearer ${PASSWORD}" \
    -H 'Content-Type: application/json' \
    "${ENDPOINT}/v1/chat/completions" \
    -d "{\"model\":\"${MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hello in one word\"}],\"max_tokens\":10}" 2>/dev/null) || true
if echo "${_response}" | jq -e '.choices[0].message.content' >/dev/null 2>&1; then
    report PASS "Chat completion (non-streaming)"
else
    report FAIL "Chat completion (non-streaming)"
fi

# Test 7: Streaming chat completion
if curl -sk --max-time "${TIMEOUT}" -H "Authorization: Bearer ${PASSWORD}" \
    -H 'Content-Type: application/json' \
    "${ENDPOINT}/v1/chat/completions" \
    -d "{\"model\":\"${MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hi\"}],\"max_tokens\":5,\"stream\":true}" 2>/dev/null \
    | grep -q 'data:'; then
    report PASS "Chat completion (streaming SSE)"
else
    report FAIL "Chat completion (streaming SSE)"
fi

# Summary
echo ""
echo "Result: ${_pass}/${_total} tests passed"
if [ "${_fail}" -gt 0 ]; then
    exit 1
fi
