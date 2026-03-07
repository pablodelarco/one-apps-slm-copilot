# Virt8ra Demo: Multi-Site SLM-Copilot Deployment

Sovereign AI coding copilot running Devstral Small 2 (24B) on CPU across multiple OpenNebula zones, federated through a central LiteLLM load balancer.

## Architecture

```
                         Users / IDE clients
                                |
                          port 8443 (TLS)
                                |
                    +-----------v-----------+
                    |   France LB (LiteLLM) |  192.168.101.101
                    |   + local llama-server |
                    +-----------+-----------+
                          |     |     |
              +-----------+     |     +-----------+
              |                 |                 |
     Tailscale tunnel   Tailscale tunnel   Tailscale tunnel
              |                 |                 |
   +----------v---+  +---------v----+  +----------v---+
   | Poland       |  | UK           |  | Spain        |
   | 192.168.102  |  | 192.168.103  |  | 192.168.104  |
   | .100 backend |  | .100 backend |  | .100 backend |
   | 15 vCPU      |  | 8 vCPU       |  | 20 vCPU      |
   +--------------+  +--------------+  +--------------+

Each site has:
  - VR VM (.99) running Tailscale as subnet router
  - SLM-Copilot VM (.100) running llama-server
  - virbr0 bridge on 192.168.{SITE_ID}.0/24
```

## Site Registry

| Site | Subnet | Host IP (public) | Host SSH | VR Tailscale | Backend Model Name |
|------|--------|-------------------|----------|--------------|-------------------|
| France (LB) | 192.168.101.0/24 | 195.154.103.94 | `ssh root@100.123.42.13` | vr-france | devstral-small-2 |
| Poland | 192.168.102.0/24 | 151.115.91.50 | `ssh root@100.84.125.71` | vr-poland | devstral-small-2-poland |
| UK | 192.168.103.0/24 | 57.128.188.10 | `ssh root@100.94.160.40` | vr-uk | devstral-small-2-uk |
| Spain | 192.168.104.0/24 | 185.99.184.102 | `ssh -i KEY ubuntu@185.99.184.102` | vr-spain | devstral-small-2-spain |

Convention: site ID increments per site (101, 102, 103, 104...). VR is always `.99`, first backend is `.100`.

## France LB Details

- VM 77 at 192.168.101.101, API key: `sk-latJ1aJrSQWGkQW6TCY6he52262nT6a9PNpgaUJOQf8Sop7X`
- LiteLLM proxy on 0.0.0.0:8443, local llama-server on 127.0.0.1:8444
- Web UI: https://192.168.101.101:8443/ui (admin / api_key)
- Remote backends register via LiteLLM `/model/new` API on boot

---

## Deploying a New Backend Site

### Prerequisites

- SSH access to the new OpenNebula host
- The SLM-Copilot QCOW2 image (transfer from France)
- A Tailscale account with access to the tailnet

### Step 1: Prepare the Host

Choose the next subnet ID (e.g., 192.168.105.0/24 for site 5).

```bash
# Extend root LV (Ubuntu defaults to 100G even on large disks)
sudo lvextend -L 300G /dev/ubuntu-vg/ubuntu-lv
sudo resize2fs /dev/ubuntu-vg/ubuntu-lv

# Reconfigure libvirt default network with the new subnet
sudo virsh net-destroy default
sudo virsh net-undefine default

cat > /tmp/net-default.xml << 'EOF'
<network>
  <name>default</name>
  <forward mode="nat">
    <nat><port start="1024" end="65535"/></nat>
  </forward>
  <bridge name="virbr0" stp="on" delay="0"/>
  <ip address="192.168.{SITE_ID}.1" netmask="255.255.255.0">
    <dhcp>
      <range start="192.168.{SITE_ID}.2" end="192.168.{SITE_ID}.254"/>
    </dhcp>
  </ip>
</network>
EOF

sudo virsh net-define /tmp/net-default.xml
sudo virsh net-start default
sudo virsh net-autostart default
```

### Step 2: Create OpenNebula Network

```bash
cat > /tmp/vnet.txt << 'EOF'
NAME="slm-copilot-net"
VN_MAD="bridge"
BRIDGE="virbr0"
BRIDGE_TYPE="linux"
NETWORK_ADDRESS="192.168.{SITE_ID}.0"
NETWORK_MASK="255.255.255.0"
GATEWAY="192.168.{SITE_ID}.1"
DNS="8.8.8.8"
SECURITY_GROUPS="0"
AR=[
  IP="192.168.{SITE_ID}.100",
  SIZE="10",
  TYPE="IP4"
]
EOF
onevnet create /tmp/vnet.txt

# Add VR address range
onevnet addar 0 --ip 192.168.{SITE_ID}.99 --size 1
```

### Step 3: Download VR Image

```bash
oneimage create \
  --name "Service Virtual Router" \
  --path "https://marketplace.opennebula.io/appliance/cc96d537-f6c7-499f-83f1-15ac4058750e/download/0" \
  --prefix vd --datastore default --type OS
```

Wait for `oneimage show 0 | grep STATE` to show `rdy`.

### Step 4: Transfer SLM-Copilot Image

From the France host (use **public IPs**, Tailscale is too slow ~200KB/s vs ~57MB/s):

```bash
# On France host
scp -i KEY /var/lib/one/datastores/1/IMAGE_HASH user@NEW_HOST_PUBLIC_IP:/var/tmp/slm-copilot.qcow2
```

Register the image on the new host:

```bash
oneimage create \
  --name "slm-copilot-2.3" \
  --path /var/tmp/slm-copilot.qcow2 \
  --prefix vd --datastore default --type OS --size 61440
```

Wait for `rdy` state. If scheduling fails with "Not enough capacity", run `onehost forceupdate 0` (as oneadmin) to refresh disk capacity after the LV resize.

### Step 5: Create VR VM

```bash
cat > /tmp/vr-vm.txt << 'EOF'
NAME="vr-tailscale"
CPU="1"
VCPU="1"
MEMORY="1024"
OS=[ARCH="x86_64"]
DISK=[IMAGE_ID="0",DEV_PREFIX="vd"]
NIC=[NETWORK_ID="0",IP="192.168.{SITE_ID}.99"]
GRAPHICS=[TYPE="VNC",LISTEN="0.0.0.0"]
CONTEXT=[
  NETWORK="YES",
  ONEAPP_VNF_ROUTER4_ENABLED="YES",
  SSH_PUBLIC_KEY="<oneadmin public key from host>"
]
EOF
onevm create /tmp/vr-vm.txt
```

### Step 6: Configure VR (Tailscale)

SSH into the VR from the host:

```bash
sudo -u oneadmin ssh root@192.168.{SITE_ID}.99
```

**Install Tailscale (latest static binary, not the Alpine package which is outdated):**

```bash
# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# Install latest Tailscale (check https://pkgs.tailscale.com/stable/ for current version)
VERSION="1.94.2"
wget -qO /tmp/tailscale.tgz https://pkgs.tailscale.com/stable/tailscale_${VERSION}_amd64.tgz
tar -xzf /tmp/tailscale.tgz -C /tmp/
cp /tmp/tailscale_${VERSION}_amd64/tailscale /usr/bin/
cp /tmp/tailscale_${VERSION}_amd64/tailscaled /usr/sbin/
rm -rf /tmp/tailscale*

# Start tailscaled
mkdir -p /var/lib/tailscale
tailscaled --state=/var/lib/tailscale/tailscaled.state --port 41641 > /var/log/tailscaled.log 2>&1 &
sleep 2

# Authenticate and advertise subnet
tailscale up --advertise-routes=192.168.{SITE_ID}.0/24 --hostname=vr-{SITE_NAME} --accept-routes
```

This prints a URL - visit it to authenticate. Then **approve the subnet route** in the Tailscale admin console (https://login.tailscale.com/admin/machines).

**Create the OpenRC init script** (copy this file to `/etc/init.d/tailscale`):

```bash
#!/sbin/openrc-run

TAILSCALED_LOGFILE="${TAILSCALED_LOGFILE:-/var/log/${RC_SVCNAME}d.log}"
TAILSCALED_PORT="${TAILSCALED_PORT:-41641}"

supervisor=supervise-daemon

name="tailscaled"
command="/usr/sbin/tailscaled"
command_args="--state=/var/lib/tailscale/tailscaled.state --port ${TAILSCALED_PORT} ${TAILSCALED_OPTS} >>${TAILSCALED_LOGFILE} 2>&1"

output_log=${TAILSCALED_LOGFILE}
error_log=${TAILSCALED_LOGFILE}

pidfile="/run/tailscaled.pid"
respawn_delay=5
respawn_max=0

depend() {
	need net
	after firewall
	use logger
}

start_pre() {
	checkpath -f -m 0644 -o root:root "${TAILSCALED_LOGFILE}"
}
```

```bash
chmod +x /etc/init.d/tailscale
rc-update add tailscale default
```

### Step 7: Add Cross-Site Routes on Backend Host

The backend host needs static routes to reach other sites via the VR VM:

```bash
ip route add 192.168.101.0/24 via 192.168.{SITE_ID}.99 dev virbr0
ip route add 192.168.102.0/24 via 192.168.{SITE_ID}.99 dev virbr0
ip route add 192.168.103.0/24 via 192.168.{SITE_ID}.99 dev virbr0
# ... add for all other site subnets
echo 1 > /proc/sys/net/ipv4/ip_forward
```

**Persist with a systemd service** (`/etc/systemd/system/cross-site-routes.service`):

```ini
[Unit]
Description=Cross-site routes via VR for SLM-Copilot
After=network.target libvirtd.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c "sleep 10; \
  ip route add 192.168.101.0/24 via 192.168.{SITE_ID}.99 dev virbr0 2>/dev/null; \
  ip route add 192.168.102.0/24 via 192.168.{SITE_ID}.99 dev virbr0 2>/dev/null; \
  ip route add 192.168.103.0/24 via 192.168.{SITE_ID}.99 dev virbr0 2>/dev/null; \
  echo 1 > /proc/sys/net/ipv4/ip_forward"

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload
systemctl enable cross-site-routes.service
```

### Step 8: Create SLM-Copilot VM

```bash
cat > /tmp/copilot-vm.txt << 'EOF'
NAME="SLM-Copilot {SITE_NAME}"
CPU="{VCPU_COUNT}"
VCPU="{VCPU_COUNT}"
MEMORY="32768"
CPU_MODEL=[MODEL="host-passthrough"]
NIC_DEFAULT=[MODEL="virtio"]
OS=[ARCH="x86_64",BOOT="disk0"]
DISK=[IMAGE_ID="1",DEV_PREFIX="vd"]
NIC=[NETWORK_ID="0",IP="192.168.{SITE_ID}.100"]
GRAPHICS=[TYPE="VNC",LISTEN="0.0.0.0"]
CONTEXT=[
  NETWORK="YES",
  ONEAPP_COPILOT_AI_MODEL="Devstral Small 2 (24B ~14GB built-in)",
  ONEAPP_COPILOT_CONTEXT_SIZE="32768",
  ONEAPP_COPILOT_CPU_THREADS="0",
  ONEAPP_COPILOT_REGISTER_KEY="sk-latJ1aJrSQWGkQW6TCY6he52262nT6a9PNpgaUJOQf8Sop7X",
  ONEAPP_COPILOT_REGISTER_MODEL_NAME="devstral-small-2-{SITE_NAME}",
  ONEAPP_COPILOT_REGISTER_URL="https://192.168.101.101:8443",
  SSH_PUBLIC_KEY="<oneadmin public key>"
]
EOF
onevm create /tmp/copilot-vm.txt
```

The VM will bootstrap automatically: download model, start llama-server, generate API key, and register with the France LB.

### Step 9: Update France LB Host (CRITICAL)

The France host has a catch-all DNAT rule that redirects all port-8443 traffic to the LB VM. Without a NETMAP exception, cross-site traffic from the LB to the new backend gets redirected back to itself.

On the France host (`ssh root@100.123.42.13`):

```bash
# Add NETMAP pass-through rule for the new subnet BEFORE the DNAT catch-all
iptables-legacy -t nat -I PREROUTING 1 \
  -i virbr0 -s 192.168.101.0/24 -d 192.168.{SITE_ID}.0/24 \
  -j NETMAP --to 192.168.{SITE_ID}.0/24

# Add MASQUERADE for cross-site NAT
iptables-legacy -t nat -A POSTROUTING \
  -s 192.168.101.0/24 -d 192.168.{SITE_ID}.0/24 \
  -o tailscale0 -j MASQUERADE
```

**Update the persistent service** at `/etc/systemd/system/iptables-nat-copilot.service` to include the new subnet, then `systemctl daemon-reload`.

### Step 10: Verify

```bash
# Check model list on LB
curl -sk -H "Authorization: Bearer sk-latJ1aJrSQWGkQW6TCY6he52262nT6a9PNpgaUJOQf8Sop7X" \
  https://192.168.101.101:8443/v1/models | python3 -m json.tool

# Test inference through new backend
curl -sk -H "Authorization: Bearer sk-latJ1aJrSQWGkQW6TCY6he52262nT6a9PNpgaUJOQf8Sop7X" \
  -H "Content-Type: application/json" \
  -d '{"model":"devstral-small-2-{SITE_NAME}","messages":[{"role":"user","content":"Hello"}],"max_tokens":20}' \
  https://192.168.101.101:8443/v1/chat/completions
```

If registration didn't happen automatically (stuck curl due to routes not being ready), manually register:

```bash
curl -sk -X POST "https://192.168.101.101:8443/model/new" \
  -H "Authorization: Bearer sk-latJ1aJrSQWGkQW6TCY6he52262nT6a9PNpgaUJOQf8Sop7X" \
  -H "Content-Type: application/json" \
  -d '{
    "model_name": "devstral-small-2-{SITE_NAME}",
    "litellm_params": {
      "model": "openai/devstral-small-2-{SITE_NAME}",
      "api_key": "<backend API key from /var/lib/slm-copilot/password>",
      "api_base": "https://192.168.{SITE_ID}.100:8443/v1",
      "ssl_verify": false
    },
    "model_info": {
      "id": "devstral-small-2-{SITE_NAME}-192.168.{SITE_ID}.100"
    }
  }'
```

---

## Troubleshooting

### Backend times out from LB

**Cause:** Missing NETMAP rule on France host. The DNAT catch-all intercepts traffic.

**Debug:**
```bash
# On France host, tcpdump virbr0 for traffic to remote backend
tcpdump -i virbr0 host 192.168.{SITE_ID}.100 -n
# If SYN packets appear but no response, check PREROUTING:
nft list chain ip nat PREROUTING
# Ensure NETMAP rule for the subnet exists BEFORE the DNAT rule
```

### VM stuck in PENDING ("Not enough capacity")

**Cause:** OpenNebula checks declared image size (60G) against system DS free space.

**Fix:** Extend the root LV and force monitoring refresh:
```bash
lvextend -L 300G /dev/ubuntu-vg/ubuntu-lv && resize2fs /dev/ubuntu-vg/ubuntu-lv
sudo -u oneadmin onehost forceupdate 0
```

### Registration curl hangs on backend VM

**Cause:** Cross-site routes weren't set up before the VM booted. The registration curl opens a TCP connection that never completes, and stays stuck even after routes are fixed.

**Fix:** Kill the stuck curl, then manually register (see Step 10) or reboot the VM.

### France host iptables commands fail with "incompatible, use nft"

**Cause:** The host uses nftables backend. Use `iptables-legacy` instead of `iptables`.

### SCP between sites is slow

Use **public IPs** (~57MB/s) instead of Tailscale IPs (~200KB/s).
