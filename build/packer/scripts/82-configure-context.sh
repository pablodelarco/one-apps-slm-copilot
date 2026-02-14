#!/usr/bin/env bash
# Move one-apps context hooks into the OpenNebula context.d directory

set -euo pipefail

CONTEXT_DIR="/etc/one-context.d"

mkdir -p "${CONTEXT_DIR}"

for script in net-90-service-appliance net-99-report-ready; do
    if [ -f "/tmp/${script}" ]; then
        mv "/tmp/${script}" "${CONTEXT_DIR}/${script}"
        chmod 0755 "${CONTEXT_DIR}/${script}"
    fi
done
