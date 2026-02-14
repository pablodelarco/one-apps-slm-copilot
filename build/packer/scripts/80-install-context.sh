#!/usr/bin/env bash

# Download and install the one-context package.
# Matches the one-apps approach.

: "${CTXEXT:=deb}"

policy_rc_d_disable() (echo "exit 101" >/usr/sbin/policy-rc.d && chmod a+x /usr/sbin/policy-rc.d)
policy_rc_d_enable()  (echo "exit 0"   >/usr/sbin/policy-rc.d && chmod a+x /usr/sbin/policy-rc.d)

exec 1>&2
set -eux -o pipefail

export DEBIAN_FRONTEND=noninteractive

# Ensure apt lists are fresh (cloud images may ship without them)
apt-get update -qq

ls -lha /context/

LATEST=$(find /context/ -type f -name "one-context*.$CTXEXT" | sort -V | tail -n1)

policy_rc_d_disable

dpkg -i --auto-deconfigure "$LATEST" || apt-get install -y -f
dpkg -i --auto-deconfigure "$LATEST"

apt-get install -y haveged

systemctl enable haveged

# Apply only on one-context >= 6.1: install netplan.io and network-manager
if ! dpkg-query -W --showformat '${Version}' one-context | grep -E '^([1-5]\.|6\.0\.)'; then
    apt-get install -y --no-install-recommends --no-install-suggests netplan.io network-manager
fi

policy_rc_d_enable

sync
