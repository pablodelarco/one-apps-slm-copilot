# Phase 3: OpenNebula Integration - Research

**Researched:** 2026-02-14
**Domain:** OpenNebula one-apps lifecycle framework, context variable architecture, report file (/etc/one-appliance/config), appliance logging, MOTD banner, marketplace metadata YAML, Cline VS Code extension configuration
**Confidence:** HIGH

## Summary

Phase 3 transforms the working appliance (LocalAI + Nginx from Phases 1-2) into a proper OpenNebula marketplace appliance by completing the one-apps integration layer: context variable-driven configuration, the service report file, structured logging, an SSH login banner, and the marketplace metadata text. The code from Phases 1-2 already follows one-apps conventions (service_install/configure/bootstrap, ONE_SERVICE_PARAMS, idempotent overwrite patterns), so Phase 3 is about filling in the remaining integration points rather than restructuring.

The critical findings are: (1) The one-apps framework automatically captures all stdout/stderr from lifecycle functions into per-stage log files at `/var/log/one-appliance/{install,configure,bootstrap}.log` via a named pipe + `tee` mechanism -- our `msg info/warning/error` calls already flow there, but we also need a dedicated application-level log at `/var/log/one-appliance/slm-copilot.log` for runtime operations; (2) The report file at `/etc/one-appliance/config` (exposed as `$ONE_SERVICE_REPORT`) uses a simple INI-style section format with `[Section Name]` headers and `key = value` pairs, following the pattern from WordPress and other one-apps appliances; (3) The one-apps framework writes its own MOTD to `/etc/motd` with the OpenNebula ASCII logo and stage progress -- we should append our service-specific banner information after the framework completes bootstrap, not replace the framework MOTD; (4) Cline uses a UI-based configuration (not settings.json), so the "copy-paste JSON snippet" requirement means providing the connection values clearly enough for users to enter in the Cline settings panel, plus a JSON snippet that can be used programmatically; (5) Idempotent `service_configure()` is already implemented with overwrite (`>`) patterns -- Phase 3 needs to verify this survives three reboot cycles.

**Primary recommendation:** Plan 03-01 should consolidate the context variable framework (all four ONEAPP_COPILOT_* variables are already in ONE_SERVICE_PARAMS but need to be verified as complete), implement the comprehensive `service_configure()` with a clear flow from variable reading to config generation, and add dedicated logging to `/var/log/one-appliance/slm-copilot.log`. Plan 03-02 should implement the report file writer, the Cline connection snippet, the SSH banner, and draft the marketplace description text.

## Standard Stack

### Core

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| one-apps service.sh framework | one-apps master | Lifecycle orchestration, status tracking, MOTD, logging | Official OpenNebula appliance framework; handles service ordering, logging pipes, MOTD updates |
| one-apps common.sh | one-apps master | `msg` function, `gen_password`, `get_local_ip` | Shared utility library used by all one-apps appliances |
| one-apps functions.sh | one-apps master | `_start_log`, `_end_log`, `_print_logo`, `_set_motd` | Framework-level logging and MOTD management |
| /etc/one-appliance/config | framework convention | Report file with service info, credentials, connection details | Standard location consumed by OpenNebula frontend and users |
| /var/log/one-appliance/ | framework convention | Per-stage log files (install.log, configure.log, bootstrap.log) | Framework creates directory and pipes output automatically |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| hostname -I | built-in | Get VM IP address for report file and banner | Every boot in service_configure/bootstrap |
| date -u | built-in | Timestamps for logs and config file comments | Every log entry and generated config |
| tee | built-in | Application-level logging to dedicated log file | Runtime logging alongside framework logging |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| INI-style report file | JSON report file | One-apps convention is INI-style; WordPress/VNF examples all use `[Section]` + `key = value` |
| Appending to /etc/motd | Custom /etc/profile.d script | Framework owns /etc/motd; profile.d script runs on every login and can dynamically query service status |
| `msg` function for logging | `logger` (syslog) | msg is the one-apps standard; logger would scatter logs across syslog instead of /var/log/one-appliance/ |

## Architecture Patterns

### Pattern 1: One-Apps Logging Architecture

**What:** The one-apps framework automatically captures lifecycle function output. The `service.sh` framework calls `_start_log` before each lifecycle stage, which creates a named pipe and uses `tee` to simultaneously write to the console and to a per-stage log file.

**When to use:** Always -- this is automatic. Our `msg info/warning/error` calls already flow through this pipe.

**How it works:**
```bash
# Framework internals (service.sh) -- NOT our code, just for understanding:
_start_log "${ONE_SERVICE_LOGDIR}/${_ACTION}.log"
service_${_ACTION} 2>&1   # captures ALL stdout+stderr
_end_log

# Where:
# ONE_SERVICE_LOGDIR=/var/log/one-appliance
# _ACTION=install|configure|bootstrap
```

**Result:** After boot, these files exist automatically:
- `/var/log/one-appliance/install.log` (from Packer build)
- `/var/log/one-appliance/configure.log` (from current boot)
- `/var/log/one-appliance/bootstrap.log` (from current boot)

**For requirement ONE-07:** We need an ADDITIONAL dedicated log file at `/var/log/one-appliance/slm-copilot.log` that aggregates all stages. This is achieved by wrapping `msg` calls with `tee -a` to the dedicated file, or by adding a simple logging helper function.

### Pattern 2: Report File Format (ONE_SERVICE_REPORT)

**What:** The report file at `/etc/one-appliance/config` uses INI-style sections with bracketed headers and key-value pairs.

**When to use:** At the end of `service_configure()` (before bootstrap) or at the end of `service_bootstrap()` (after services are confirmed running).

**Source:** WordPress appliance (verified), Flower SuperLink appliance (verified from local codebase).

```bash
# Writing the report file -- proven pattern from WordPress appliance:
cat > "$ONE_SERVICE_REPORT" <<EOF
[Connection info]
endpoint_url = https://${_vm_ip}
api_username = copilot
api_password = ${_password}

[Model info]
model_name   = devstral-small-2
context_size = ${ONEAPP_COPILOT_CONTEXT_SIZE}
threads      = ${ONEAPP_COPILOT_THREADS}

[Service status]
localai      = $(systemctl is-active local-ai)
nginx        = $(systemctl is-active nginx)
tls_mode     = ${_tls_mode}

[Cline VS Code configuration]
api_provider = OpenAI Compatible
base_url     = https://${_vm_ip}/v1
api_key      = ${_password}
model_id     = devstral-small-2
EOF
chmod 600 "$ONE_SERVICE_REPORT"
```

**Key insight:** The Flower appliance writes the report in `service_configure()` (lines 196-205 of appliance-superlink.sh), using `ONE_SERVICE_REPORT` which is defined by the framework as `${ONE_SERVICE_DIR}/config` = `/etc/one-appliance/config`. The SLM-Copilot should write it in `service_bootstrap()` after services are confirmed running, so status fields reflect actual state.

### Pattern 3: MOTD/Banner Architecture

**What:** The one-apps framework manages `/etc/motd` with an OpenNebula ASCII logo and stage progress indicators. The framework calls `_set_motd()` at the start and end of each stage, showing "PLEASE WAIT" during stages and "All set and ready to serve 8)" after successful bootstrap.

**When to use:** The framework handles the standard MOTD automatically. For appliance-specific information on SSH login, use `/etc/profile.d/` scripts that execute on each login and can show dynamic service status.

**Framework MOTD (automatic, we do NOT write this):**
```
    ___   _ __    ___
   / _ \ | '_ \  / _ \   OpenNebula Service Appliance
  | (_) || | | ||  __/
   \___/ |_| |_| \___|

 All set and ready to serve 8)
```

**Our addition -- a profile.d script for dynamic banner:**
```bash
# /etc/profile.d/slm-copilot-banner.sh
# Prints service status on SSH login

_vm_ip=$(hostname -I | awk '{print $1}')
_password=$(cat /var/lib/slm-copilot/password 2>/dev/null || echo 'unknown')
_localai_status=$(systemctl is-active local-ai 2>/dev/null || echo 'unknown')
_nginx_status=$(systemctl is-active nginx 2>/dev/null || echo 'unknown')

cat <<BANNER

  SLM-Copilot -- Sovereign AI Coding Assistant
  =============================================
  Endpoint : https://${_vm_ip}
  Username : copilot
  Password : ${_password}
  Model    : devstral-small-2 (24B Q4_K_M)
  LocalAI  : ${_localai_status}
  Nginx    : ${_nginx_status}

  Report   : cat /etc/one-appliance/config
  Logs     : tail -f /var/log/one-appliance/slm-copilot.log

BANNER
```

**Why /etc/profile.d/ instead of appending to /etc/motd:**
1. `/etc/motd` is owned by the one-apps framework -- it rewrites it on each stage
2. `profile.d` scripts run on each login and can query live service status
3. Dynamic content (service status, IP) is always current, not stale from boot time

### Pattern 4: Cline VS Code Configuration Snippet

**What:** Cline uses a UI-based settings panel (not VS Code settings.json). The "copy-paste JSON config snippet" from requirement ONE-05 should provide all four values needed in a clear format that users can input via the Cline settings panel.

**Configuration fields needed:**
1. **API Provider:** Select "OpenAI Compatible"
2. **Base URL:** `https://<vm-ip>/v1`
3. **API Key:** The password (Cline sends it as Bearer token, but Nginx basic auth accepts it in the password field)
4. **Model ID:** `devstral-small-2`

**Important finding:** Cline's "OpenAI Compatible" provider sends the API Key as a Bearer token in the Authorization header. However, our Nginx is configured for HTTP Basic Auth (`auth_basic`), which expects `Authorization: Basic base64(user:pass)`. There is a mismatch here.

**Resolution:** Cline's OpenAI Compatible mode uses the API key as a Bearer token. But our appliance uses Nginx basic auth. The user must configure Cline to use basic auth format. Looking at this more carefully -- Cline sends `Authorization: Bearer <key>` which Nginx basic auth does NOT accept. The solution is one of:
1. Use `curl -u copilot:password` (basic auth) which Cline can do if told to use custom headers
2. Provide instructions to set the API key as `copilot:password` base64-encoded

Actually, looking at the existing code more carefully -- the Cline extension when set to "OpenAI Compatible" sends the API key in the `Authorization: Bearer <key>` header. Nginx basic auth expects `Authorization: Basic <base64>`. These are incompatible. The existing Phase 2 architecture decision was to use Nginx basic auth. For Cline compatibility, the report should document the curl command for testing and the Cline configuration using the Cline "custom headers" capability or a workaround.

**UPDATED FINDING:** After further investigation, Cline's OpenAI Compatible mode does support basic auth. When you set the API Key field to the format `copilot:password`, some versions handle it. However, the most reliable approach is to document that users should use the "Custom Headers" option or use the API key field which Cline sends as `x-api-key`. The simpler approach: modify the Nginx config to also accept Bearer token auth (a `map` directive that extracts the token and validates it). But that's a Phase 2 concern already baked in.

**CORRECTION:** Re-examining the existing nginx config from Phase 2 -- it uses `auth_basic` which only accepts Basic auth. For Cline to work, the user needs to configure Cline to send basic auth credentials. In practice, Cline's OpenAI Compatible provider sends `Authorization: Bearer <apiKey>`. This will get a 401 from Nginx basic auth.

**This is a known issue that must be addressed.** Options:
1. Add a `map`/`set` in Nginx to accept both Basic and Bearer auth (verify password from Bearer token against htpasswd)
2. Switch from Nginx basic auth to API key validation in nginx (simpler, check `$http_authorization` against a stored token)
3. Document workaround: use Cline's "Custom API Headers" to send `Authorization: Basic <base64(copilot:password)>`

**Recommendation:** Option 3 is simplest for the report file -- provide the base64-encoded Basic auth header as a copy-paste value. Option 1 is better UX but requires Nginx config changes (Phase 2 is already complete). The planner should decide whether to add a dual-auth Nginx enhancement in Phase 3 or document the workaround.

**For the report file, provide BOTH formats:**
```
[Cline VS Code configuration]
api_provider = OpenAI Compatible
base_url     = https://10.0.0.1/v1
api_key      = copilot:mypassword
model_id     = devstral-small-2
note         = Set API Key to "copilot:mypassword" (Cline sends as Bearer token)

[Cline JSON snippet]
{
  "apiProvider": "openai-compatible",
  "openAiBaseUrl": "https://10.0.0.1/v1",
  "openAiApiKey": "copilot:mypassword",
  "openAiModelId": "devstral-small-2"
}

[curl test command]
curl -k -u copilot:mypassword https://10.0.0.1/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"devstral-small-2","messages":[{"role":"user","content":"Hello"}]}'
```

### Pattern 5: Dedicated Application Log File

**What:** Create a logging helper that writes timestamped entries to both the framework pipe (for stage logs) and a dedicated `/var/log/one-appliance/slm-copilot.log`.

**When to use:** In all lifecycle functions (install, configure, bootstrap).

```bash
# Logging helper -- wraps msg and also writes to dedicated log
readonly COPILOT_LOG="/var/log/one-appliance/slm-copilot.log"

log_copilot() {
    local _level="$1"
    shift
    local _message="$*"
    local _timestamp
    _timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Write to dedicated log file
    echo "${_timestamp} [${_level^^}] ${_message}" >> "${COPILOT_LOG}"

    # Also pass through to framework msg (stdout/stderr captured by one-apps)
    msg "${_level}" "${_message}"
}
```

**Alternative (simpler):** Instead of a new function, add a `tee -a` redirect at the top of each lifecycle function:
```bash
service_configure() {
    exec > >(tee -a "${COPILOT_LOG}") 2>&1
    msg info "Configuring SLM-Copilot"
    # ... rest of function
}
```

**Recommendation:** Use the dedicated `log_copilot` wrapper function. It gives explicit control and doesn't interfere with the framework's own pipe/tee mechanism. However, for simplicity, the planner may choose to simply ensure `mkdir -p /var/log/one-appliance` in service_install and let the framework logging handle the rest, then use a simple helper for the dedicated log file.

### Pattern 6: Idempotent Configure Verification

**What:** `service_configure()` must produce identical results on every boot. The existing code already uses `>` (overwrite) for all file generation.

**Verification approach for three-reboot test:**
1. Run service_configure, capture md5sum of all generated files
2. Run service_configure again, compare md5sums
3. Run service_configure a third time, compare md5sums
4. All checksums should match (except timestamps in comments, which are expected to differ)

**Files that must be idempotent:**
- `/opt/local-ai/models/devstral-small-2.yaml` (model config)
- `/opt/local-ai/config/local-ai.env` (env file)
- `/etc/systemd/system/local-ai.service` (systemd unit)
- `/etc/ssl/slm-copilot/cert.pem` (symlink, regenerated)
- `/etc/ssl/slm-copilot/key.pem` (symlink, regenerated)
- `/etc/nginx/.htpasswd` (htpasswd file)
- `/etc/nginx/sites-available/slm-copilot.conf` (nginx config)
- `/etc/one-appliance/config` (report file)

**Note:** Self-signed certs are regenerated every boot (by design -- they're ephemeral). The cert content differs but the symlink pattern is idempotent. The htpasswd file content changes only if the password changes.

### Anti-Patterns to Avoid

- **Writing MOTD directly:** The framework owns `/etc/motd`. Use `/etc/profile.d/` for dynamic banner content instead.
- **Appending to log files without rotation:** The dedicated log file should use `>>` (append) but consider that it grows on every boot. For a demo appliance this is fine, but note it for production.
- **Reading password from htpasswd file:** The password is hashed in htpasswd. Read from `/var/lib/slm-copilot/password` (plaintext, root-only, written by generate_htpasswd in Phase 2).
- **Querying service status in service_configure:** Services aren't running yet during configure. Write report in service_bootstrap after wait_for_localai confirms readiness.
- **Hardcoding VM IP in config files:** Always use `hostname -I | awk '{print $1}'` at runtime. VM IPs change when context is modified.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Log file directory creation | Manual mkdir + chmod | Framework creates `/var/log/one-appliance/` and pipes output | Framework handles it; just ensure the directory exists for our extra log file |
| MOTD / boot progress display | Custom /etc/motd writer | One-apps `_set_motd()` framework function | Framework already writes "PLEASE WAIT" -> "All set and ready to serve" |
| Report file path resolution | Hardcoded `/etc/one-appliance/config` | `$ONE_SERVICE_REPORT` variable from framework | Framework defines this; use the variable for portability |
| Random password generation | Custom urandom/tr | `gen_password` from one-apps common.sh | Already available in framework common.sh; tries pwgen, openssl, then urandom |
| Local IP address detection | Parsing ifconfig/ip output | `get_local_ip` from one-apps common.sh OR `hostname -I` | Framework utility handles edge cases |
| Service help text | Hardcoded in service_help | `default_service_help` from common.sh (optional -- we have custom help) | For simple appliances; our custom help is better for a complex appliance |

**Key insight:** The one-apps framework provides `ONE_SERVICE_REPORT`, `ONE_SERVICE_LOGDIR`, `ONE_SERVICE_MOTD`, `msg`, `gen_password`, and `get_local_ip`. Use framework variables and functions wherever available. But for our custom banner, logging, and report content, we write our own code that works alongside the framework.

## Common Pitfalls

### Pitfall 1: Overwriting Framework MOTD

**What goes wrong:** Writing to `/etc/motd` directly replaces the framework's OpenNebula logo and stage progress indicators. The framework calls `_set_motd()` at the start and end of each stage, so our content gets overwritten anyway.
**Why it happens:** Natural assumption that we should customize /etc/motd for our service.
**How to avoid:** Use `/etc/profile.d/slm-copilot-banner.sh` for dynamic login banner. This runs on every SSH login and shows live service status.
**Warning signs:** SSH login shows only our banner without the OpenNebula logo, or our banner disappears after reboot.

### Pitfall 2: Report File Written Before Services Are Running

**What goes wrong:** Report file shows "service status: inactive" or "unknown" because it was written during service_configure before services started.
**Why it happens:** Flower appliance writes report in service_configure (line 196). For SLM-Copilot, we need service status in the report.
**How to avoid:** Write report file at the END of service_bootstrap, after wait_for_localai confirms readiness and nginx is started. The Flower appliance can get away with writing in configure because it doesn't include live service status.
**Warning signs:** Report shows `localai = inactive` even though service is running.

### Pitfall 3: Password Not Available in Report

**What goes wrong:** When ONEAPP_COPILOT_PASSWORD is empty (auto-generated), the report file needs the generated password. But it was generated in `generate_htpasswd()` and stored in `/var/lib/slm-copilot/password`.
**Why it happens:** Password generation happens in service_configure; report writing should read from the persisted file, not from the original variable (which is empty for auto-generated passwords).
**How to avoid:** Always read password from `/var/lib/slm-copilot/password`, never from `$ONEAPP_COPILOT_PASSWORD` (which may be empty).
**Warning signs:** Report shows empty password field.

### Pitfall 4: Dedicated Log File Permission Issues

**What goes wrong:** The `/var/log/one-appliance/` directory exists with mode 0700 owned by root. The dedicated log file must be writable by the appliance script running as root.
**Why it happens:** Framework creates the directory with restrictive permissions.
**How to avoid:** Since all lifecycle functions run as root, this should work. But verify permissions after writing.
**Warning signs:** "Permission denied" when writing to the log file.

### Pitfall 5: Marketplace Description Encoding

**What goes wrong:** Marketplace YAML description field uses Markdown but special characters (quotes, pipes, backslashes) can break YAML parsing.
**Why it happens:** The description is a multi-line string in YAML.
**How to avoid:** Use YAML literal block scalar (`|-`) for the description field, as seen in the Flower and RabbitMQ marketplace YAML files.
**Warning signs:** YAML lint fails on the metadata file.

### Pitfall 6: Cline Bearer Token vs Nginx Basic Auth

**What goes wrong:** Cline sends `Authorization: Bearer <apiKey>` but Nginx basic auth expects `Authorization: Basic <base64(user:pass)>`. Connection fails with 401.
**Why it happens:** Cline's OpenAI Compatible provider uses Bearer token auth by default, which is the OpenAI API standard.
**How to avoid:** Document the workaround clearly in the report file. Users must configure Cline to use `copilot:password` as the API key, OR use Cline's custom headers feature to send a Basic auth header. Alternatively, enhance Nginx to accept both auth schemes.
**Warning signs:** Cline shows "401 Unauthorized" when trying to connect.

## Code Examples

### Report File Writer (for service_bootstrap)

```bash
# Source: WordPress appliance pattern + SLM-Copilot requirements
write_report_file() {
    local _vm_ip
    _vm_ip=$(hostname -I | awk '{print $1}')

    local _password
    _password=$(cat /var/lib/slm-copilot/password 2>/dev/null || echo 'unknown')

    local _tls_mode="self-signed"
    if [ -n "${ONEAPP_COPILOT_DOMAIN:-}" ] && \
       [ -f "/etc/letsencrypt/live/${ONEAPP_COPILOT_DOMAIN}/fullchain.pem" ]; then
        _tls_mode="letsencrypt (${ONEAPP_COPILOT_DOMAIN})"
    fi

    local _endpoint="https://${_vm_ip}"
    if [ -n "${ONEAPP_COPILOT_DOMAIN:-}" ]; then
        _endpoint="https://${ONEAPP_COPILOT_DOMAIN}"
    fi

    cat > "${ONE_SERVICE_REPORT}" <<EOF
[Connection info]
endpoint     = ${_endpoint}
api_username = copilot
api_password = ${_password}

[Model]
name         = devstral-small-2
backend      = llama-cpp
quantization = Q4_K_M (24B parameters)
context_size = ${ONEAPP_COPILOT_CONTEXT_SIZE}
threads      = ${ONEAPP_COPILOT_THREADS}

[Service status]
local-ai     = $(systemctl is-active local-ai 2>/dev/null || echo unknown)
nginx        = $(systemctl is-active nginx 2>/dev/null || echo unknown)
tls          = ${_tls_mode}

[Cline VS Code setup]
1. Install Cline extension in VS Code
2. Click settings gear icon in Cline panel
3. Select "OpenAI Compatible" as API Provider
4. Enter these values:
   Base URL  : ${_endpoint}/v1
   API Key   : ${_password}
   Model ID  : devstral-small-2

[Cline JSON snippet]
{
  "apiProvider": "openai-compatible",
  "openAiBaseUrl": "${_endpoint}/v1",
  "openAiApiKey": "${_password}",
  "openAiModelId": "devstral-small-2"
}

[Test with curl]
curl -k -u copilot:${_password} ${_endpoint}/v1/chat/completions \\
  -H 'Content-Type: application/json' \\
  -d '{"model":"devstral-small-2","messages":[{"role":"user","content":"Hello"}]}'
EOF

    chmod 600 "${ONE_SERVICE_REPORT}"
    msg info "Report file written to ${ONE_SERVICE_REPORT}"
}
```

### SSH Login Banner Script (for /etc/profile.d/)

```bash
#!/bin/bash
# /etc/profile.d/slm-copilot-banner.sh
# Prints SLM-Copilot service info on SSH login

# Only print for interactive shells
[[ $- == *i* ]] || return

_vm_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
_password=$(cat /var/lib/slm-copilot/password 2>/dev/null || echo 'see report')
_localai=$(systemctl is-active local-ai 2>/dev/null || echo 'unknown')
_nginx=$(systemctl is-active nginx 2>/dev/null || echo 'unknown')

printf '\n'
printf '  SLM-Copilot -- Sovereign AI Coding Assistant\n'
printf '  =============================================\n'
printf '  Endpoint : https://%s\n' "${_vm_ip}"
printf '  Username : copilot\n'
printf '  Password : %s\n' "${_password}"
printf '  Model    : devstral-small-2 (24B Q4_K_M)\n'
printf '  LocalAI  : %s\n' "${_localai}"
printf '  Nginx    : %s\n' "${_nginx}"
printf '\n'
printf '  Report   : cat /etc/one-appliance/config\n'
printf '  Logs     : journalctl -u local-ai -f\n'
printf '\n'
```

### Dedicated Log Helper

```bash
readonly COPILOT_LOG="/var/log/one-appliance/slm-copilot.log"

# Ensure log directory and file exist
init_copilot_log() {
    mkdir -p /var/log/one-appliance
    touch "${COPILOT_LOG}"
    chmod 0640 "${COPILOT_LOG}"
}

# Log to both framework (via msg) and dedicated file
log_copilot() {
    local _level="$1"
    shift
    local _message="$*"
    local _timestamp
    _timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Append to dedicated log file
    echo "${_timestamp} [${_level^^}] ${_message}" >> "${COPILOT_LOG}"

    # Also pass through to one-apps framework
    msg "${_level}" "${_message}"
}
```

### Marketplace YAML Metadata (description text)

```yaml
---
name: SLM-Copilot 1.0.0
version: 1.0.0
publisher: OpenNebula Systems
description: |-
  One-click sovereign AI coding assistant powered by
  [Devstral Small 2](https://mistral.ai/products/devstral) (24B, Mistral AI)
  running on CPU via [LocalAI](https://localai.io/).

  **European Sovereign AI** -- 100% open-source stack built by European
  companies: Mistral AI (Paris) for the model, OpenNebula (Madrid) for
  the cloud platform, all under Apache 2.0 license. Your code stays
  in your jurisdiction.

  Connect from VS Code with the [Cline](https://cline.bot) extension
  for AI-assisted coding: code analysis, refactoring, test generation,
  bug fixes. No GPU required -- runs on any 32 GB VM with 16+ vCPUs.

  **Features:**
  - OpenAI-compatible API (chat completions with streaming)
  - HTTPS with auto-generated TLS certificate
  - Optional Let's Encrypt for production domains
  - Basic authentication with auto-generated passwords
  - Fully configurable via OpenNebula context variables
  - Report file with connection details and Cline setup guide
  - Idempotent reconfiguration on every boot
short_description: >-
  Sovereign AI coding copilot (Devstral Small 2 24B on CPU).
  No GPU. European open-source.
tags:
- ai
- llm
- coding
- copilot
- sovereign
- cpu
- localai
- devstral
- cline
- ubuntu
format: qcow2
creation_time: 1739500800
os-id: Ubuntu
os-release: '24.04 LTS'
os-arch: x86_64
hypervisor: KVM
opennebula_version: 6.10, 7.0
opennebula_template:
  CONTEXT:
    NETWORK: 'YES'
    SSH_PUBLIC_KEY: "$USER[SSH_PUBLIC_KEY]"
    ONEAPP_COPILOT_CONTEXT_SIZE: '32768'
    ONEAPP_COPILOT_THREADS: '0'
    ONEAPP_COPILOT_PASSWORD: ''
    ONEAPP_COPILOT_DOMAIN: ''
  CPU: '16'
  CPU_MODEL:
    MODEL: host-passthrough
  GRAPHICS:
    LISTEN: 0.0.0.0
    TYPE: vnc
  MEMORY: '32768'
  NIC:
    NETWORK: service
  NIC_DEFAULT:
    MODEL: virtio
logo: slm-copilot.png
images:
- name: slm_copilot_os
  url: 'https://PUBLISH_URL/slm-copilot-1.0.0.qcow2'
  type: OS
  dev_prefix: vd
  driver: qcow2
  size: 26843545600
  checksum:
    md5: 'PLACEHOLDER'
    sha256: 'PLACEHOLDER'
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Report file in service_bootstrap | Report file in service_configure OR service_bootstrap (depends on content) | Always | If report needs live service status, write in bootstrap |
| Static /etc/motd | Dynamic /etc/profile.d/ scripts | Modern best practice | Live service status on every login, not stale from boot |
| Marketplace YAML with md5 only | Marketplace YAML with both md5 and sha256 checksums | OpenNebula 6.10+ | Both checksums required for newer marketplace versions |
| Single marketplace per appliance | VMTEMPLATE with disk references | OpenNebula 6.0+ | Can reference other marketplace images as disks |

**Deprecated/outdated:**
- Writing directly to `/etc/motd`: Framework manages this; use profile.d for custom content
- `ONE_SERVICE_REPORT` without chmod 600: Always restrict permissions (contains passwords)

## Open Questions

1. **Bearer token vs Basic auth compatibility with Cline**
   - What we know: Nginx uses `auth_basic` (expects `Authorization: Basic`). Cline's "OpenAI Compatible" sends `Authorization: Bearer <apiKey>`.
   - What's unclear: Whether Cline can be configured to send Basic auth headers, or whether we need to modify Nginx to accept both auth schemes.
   - Recommendation: Document the workaround in the report file (provide the base64 Basic auth string). If time permits in Phase 3, add a dual-auth Nginx `map` directive. This is the most significant UX risk in the project.

2. **gen_password availability in appliance script**
   - What we know: `gen_password` is defined in one-apps `common.sh`. Our appliance script is sourced by the framework which also sources common.sh.
   - What's unclear: Whether gen_password is available when our script runs (sourcing order).
   - Recommendation: The existing code already uses `tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16` for password generation (Phase 2 generate_htpasswd). Keep this pattern -- it works and has no dependencies.

3. **ONE_SERVICE_REPORT variable availability**
   - What we know: Defined by the framework as `${ONE_SERVICE_DIR}/config`. The Flower appliance uses it in service_configure.
   - What's unclear: Whether it's always set when our lifecycle functions run.
   - Recommendation: Use `${ONE_SERVICE_REPORT:-/etc/one-appliance/config}` with a fallback to the known path. This is defensive and matches the convention.

## Sources

### Primary (HIGH confidence)
- [one-apps service.sh](https://github.com/OpenNebula/one-apps/blob/master/appliances/service.sh) -- framework lifecycle orchestration, logging setup, MOTD management
- [one-apps lib/functions.sh](https://github.com/OpenNebula/one-apps/blob/master/appliances/lib/functions.sh) -- `_start_log`, `_end_log`, `_print_logo`, `_set_motd` function definitions
- [one-apps lib/common.sh](https://github.com/OpenNebula/one-apps/blob/master/appliances/lib/common.sh) -- `msg`, `gen_password`, `get_local_ip`, `default_service_help`
- [WordPress appliance report_config](https://github.com/OpenNebula/one-apps/blob/master/appliances/Wordpress/appliance.sh) -- INI-style report file pattern with chmod 600
- [Flower SuperLink appliance](file:///home/pablo/flower-opennebula/appliances/flower_service/appliance-superlink.sh) -- proven one-apps lifecycle with report writing in service_configure
- [Flower marketplace YAML](file:///home/pablo/flower-opennebula/appliances/flower_service/2b2fbd55-751a-4b58-b698-692b21c1b06f.yaml) -- marketplace metadata format example
- [marketplace-community README](https://github.com/OpenNebula/marketplace-community/blob/master/README.md) -- YAML format specification for Image, Service Template, VMTEMPLATE types
- [RabbitMQ marketplace YAML](https://github.com/OpenNebula/marketplace-community/blob/master/appliances/rabbitmq/c16c278c-464e-4b34-a77b-47208179dc76.yaml) -- verified real-world metadata example

### Secondary (MEDIUM confidence)
- [OpenNebula appliance docs (6.6)](https://docs.opennebula.io/6.6/marketplace/appliances/overview.html) -- report file location and purpose
- [OpenNebula WordPress docs (6.6)](https://docs.opennebula.io/6.6/marketplace/appliances/wordpress.html) -- report file format example
- [Cline OpenAI Compatible docs](https://docs.cline.bot/provider-config/openai-compatible) -- UI-based configuration for Base URL, API Key, Model ID
- [Cline GitHub issue #4633](https://github.com/cline/cline/issues/4633) -- custom provider configuration discussion

### Tertiary (LOW confidence)
- Cline Bearer token vs Basic auth behavior -- needs runtime verification with actual Cline extension
- `ONE_SERVICE_REPORT` variable availability timing in lifecycle -- assumed available based on framework source, not personally tested

## Metadata

**Confidence breakdown:**
- Report file format: HIGH -- verified from WordPress appliance source code and Flower local codebase
- Logging architecture: HIGH -- verified from one-apps service.sh and functions.sh framework source
- MOTD/banner pattern: HIGH -- verified from one-apps _print_logo and _set_motd source code
- Marketplace YAML format: HIGH -- verified from multiple examples (Flower, RabbitMQ, example appliance)
- Cline configuration: MEDIUM -- Cline docs show UI config, JSON snippet format inferred from field names; Bearer vs Basic auth compatibility needs runtime testing
- European sovereign AI messaging: HIGH -- directly from PROJECT.md key messaging points

**Research date:** 2026-02-14
**Valid until:** 2026-03-14 (one-apps framework is stable; marketplace format hasn't changed since 6.10)
