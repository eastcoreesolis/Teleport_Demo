#!/usr/bin/env bash
#
# prepare-network.sh
# ============================================================================
#  Prepares a single K8s node's network configuration for cluster use.
# ----------------------------------------------------------------------------
#  This script MUST be run on EACH of the 3 nodes before verify-network.sh
#  is run from the control plane.
#
#  What it does:
#    1. Writes a deterministic netplan configuration for dual-NIC setup
#       (eth0 = cluster-internal, eth1 = corporate-external)
#    2. Masks cloud-init network management (prevents overwrites on reboot)
#    3. Applies the K8s-required sysctl values (rp_filter, IP forwarding)
#    4. Adds cluster peer entries to /etc/hosts (DNS fallback)
#    5. Restarts systemd-networkd to apply the netplan
#
#  Usage:
#    sudo ./prepare-network.sh
#    (You will be prompted for the host's role, IPs, and peer nodes)
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/lib/ui.sh"
source "${SCRIPT_DIR}/lib/net-utils.sh"

# ---------- Root check ----------
if [[ $EUID -ne 0 ]]; then
  fail "This script must be run as root (use: sudo ./prepare-network.sh)"
  echo "  It modifies /etc/netplan, /etc/sysctl.d/, and /etc/hosts."
  exit 1
fi

# ---------- Welcome ----------
banner
echo "  This script prepares a single K8s node's network configuration"
echo "  for cluster use. Run it on EACH of the 3 nodes before running"
echo "  verify-network.sh from the control plane."
echo ""
echo "  ${BLD}What this script will do:${NC}"
echo "    1. Write a deterministic netplan for dual-NIC (eth0=internal, eth1=external)"
echo "    2. Mask cloud-init network management to prevent overwrites on reboot"
echo "    3. Apply K8s-required sysctl values (rp_filter, IP forwarding)"
echo "    4. Add cluster peer entries to /etc/hosts as a DNS fallback"
echo "    5. Apply all changes immediately (no reboot required)"
echo ""
read -rp "  Press ENTER to begin, or Ctrl+C to exit: " _
echo ""

# ---------- Step 1: Node role and IP configuration ----------
section "Step 1 of 4 — Node Identity and IP Configuration"
echo ""
echo "  Tell us about THIS node (the one you're running this script on)."
echo ""

# Hostname
while true; do
  default_hostname=$(hostname)
  read -rp "  This node's hostname [${default_hostname}]: " THIS_HOSTNAME
  THIS_HOSTNAME=${THIS_HOSTNAME:-$default_hostname}
  [[ -n "$THIS_HOSTNAME" ]] && break
  fail "Hostname cannot be empty."
done
ok "This node: ${BLD}${THIS_HOSTNAME}${NC}"

# Internal IP
while true; do
  read -rp "  This node's INTERNAL IP (eth0, e.g., 192.168.2.85): " THIS_INT_IP
  if is_valid_ip "$THIS_INT_IP"; then
    break
  else
    fail "'${THIS_INT_IP}' is not a valid IPv4 address."
  fi
done
ok "Internal IP: ${BLD}${THIS_INT_IP}${NC}"

# External IP
while true; do
  read -rp "  This node's EXTERNAL IP (eth1, e.g., 192.168.1.85): " THIS_EXT_IP
  if is_valid_ip "$THIS_EXT_IP"; then
    break
  else
    fail "'${THIS_EXT_IP}' is not a valid IPv4 address."
  fi
done
ok "External IP: ${BLD}${THIS_EXT_IP}${NC}"

# Default gateway (for eth1)
while true; do
  read -rp "  External default gateway (e.g., 192.168.1.254): " THIS_GATEWAY
  if is_valid_ip "$THIS_GATEWAY"; then
    break
  else
    fail "'${THIS_GATEWAY}' is not a valid IPv4 address."
  fi
done
ok "Default gateway: ${BLD}${THIS_GATEWAY}${NC}"

# DNS servers
echo ""
echo "  Enter DNS servers for the external network (eth1)."
echo "  Provide them as a comma-separated list, or press ENTER to skip."
echo ""
read -rp "  DNS servers [192.168.1.70,192.168.1.254]: " THIS_DNS
THIS_DNS=${THIS_DNS:-192.168.1.70,192.168.1.254}
ok "DNS servers: ${BLD}${THIS_DNS}${NC}"

# Search domain
echo ""
read -rp "  DNS search domain (e.g., eastcore.local) [none]: " THIS_SEARCH
if [[ -n "$THIS_SEARCH" ]]; then
  ok "Search domain: ${BLD}${THIS_SEARCH}${NC}"
else
  ok "Search domain: (none)"
fi

# ---------- Step 2: Peer nodes (for /etc/hosts) ----------
section "Step 2 of 4 — Peer Cluster Nodes"
echo ""
echo "  Enter the other 2 nodes in the cluster so they can be added to"
echo "  /etc/hosts. This provides DNS resolution as a fallback in case"
echo "  your corporate DNS doesn't have A records for the cluster nodes."
echo ""

PEERS=()
PEER_COUNT=2
read -rp "  How many peer nodes? [2]: " PEER_COUNT_INPUT
PEER_COUNT=${PEER_COUNT_INPUT:-2}

for ((i=0; i<PEER_COUNT; i++)); do
  echo -e "  ${BLD}--- Peer $((i+1)) of $PEER_COUNT ---${NC}"
  while true; do
    read -rp "    Hostname (e.g., kworkera): " pname
    [[ -n "$pname" ]] && break
    fail "Hostname cannot be empty."
  done
  while true; do
    read -rp "    Internal IP:                 " pip
    is_valid_ip "$pip" && break
    fail "Invalid IPv4 address."
  done
  PEERS+=("${pname}:${pip}")
  ok "Peer $((i+1)): ${BLD}${pname}${NC} (${pip})"
done

# ---------- Step 3: Netplan ----------
section "Step 3 of 4 — Netplan Configuration"
echo ""
echo "  The following netplan will be written to /etc/netplan/99-k8s.yaml:"
echo ""

# Build DNS list as YAML array
IFS=',' read -ra DNS_ARRAY <<< "$THIS_DNS"
DNS_YAML=""
for d in "${DNS_ARRAY[@]}"; do
  DNS_YAML="${DNS_YAML}          - ${d}
"
done

SEARCH_LINE=""
if [[ -n "$THIS_SEARCH" ]]; then
  SEARCH_LINE="          search: [${THIS_SEARCH}]"
fi

NETPLAN_CONTENT="network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: no
      dhcp6: no
      addresses:
        - ${THIS_INT_IP}/24
    eth1:
      dhcp4: no
      dhcp6: no
      addresses:
        - ${THIS_EXT_IP}/24
      routes:
        - to: 0.0.0.0/0
          via: ${THIS_GATEWAY}
          metric: 100
      nameservers:
        addresses:
${DNS_YAML}${SEARCH_LINE}
"

echo -e "${CYN}──── /etc/netplan/99-k8s.yaml ────────────────────────────────${NC}"
echo "$NETPLAN_CONTENT" | sed 's/^/    /'
echo -e "${CYN}──────────────────────────────────────────────────────────────${NC}"
echo ""
read -rp "  Apply this netplan? [Y/n]: " confirm_netplan
if [[ "$confirm_netplan" =~ ^[nN](o)?$ ]]; then
  warn "Skipping netplan application. You must configure it manually."
  APPLY_NETPLAN=false
else
  APPLY_NETPLAN=true
fi

# ---------- Step 4: Apply all changes ----------
section "Step 4 of 4 — Apply Changes"
echo ""
echo "  Applying the following changes to this node:"
[[ "$APPLY_NETPLAN" == "true" ]] && echo "    • Netplan configuration (eth0/eth1)"
echo "    • Sysctl values (rp_filter, IP forwarding)"
echo "    • Cloud-init network mask"
echo "    • /etc/hosts entries for peer nodes"
echo ""
read -rp "  Press ENTER to apply, or Ctrl+C to cancel: " _
echo ""

# ---------- 4a: Netplan ----------
if [[ "$APPLY_NETPLAN" == "true" ]]; then
  echo -e "  ${CYN}→${NC} Writing /etc/netplan/99-k8s.yaml..."
  echo "$NETPLAN_CONTENT" > /etc/netplan/99-k8s.yaml
  chmod 600 /etc/netplan/99-k8s.yaml
  
  # Remove conflicting default configs from cloud-init / netplan.io
  for f in /etc/netplan/50-cloud-init.yaml /etc/netplan/01-netcfg.yaml; do
    if [[ -f "$f" ]]; then
      echo -e "  ${CYN}→${NC} Removing conflicting ${f}..."
      mv "$f" "${f}.disabled"
    fi
  done
  
  echo -e "  ${CYN}→${NC} Applying netplan (this may briefly drop your connection)..."
  if netplan apply; then
    ok "Netplan applied successfully"
  else
    fail "Netplan apply failed. Check: netplan --debug apply"
    exit 1
  fi
else
  warn "Netplan NOT applied. Manual configuration required."
fi

# ---------- 4b: Cloud-init mask ----------
echo ""
echo -e "  ${CYN}→${NC} Masking cloud-init network configuration..."
echo "    This prevents cloud-init from overwriting the netplan on reboot."
if ln -sf /dev/null /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg 2>/dev/null; then
  ok "Cloud-init network management disabled"
else
  warn "Could not create cloud-init override (may not be present on this system)"
fi

# ---------- 4c: Sysctl values ----------
echo ""
echo -e "  ${CYN}→${NC} Writing /etc/sysctl.d/99-kubernetes.conf..."

SYSCTL_CONTENT="# Kubernetes networking requirements
# Reverse-path filtering: 1 (strict) — required for dual-NIC setups with CNIs
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.eth0.rp_filter = 1
net.ipv4.conf.eth1.rp_filter = 1

# IP forwarding: required for pod-to-pod routing across nodes
net.ipv4.ip_forward = 1

# Bridge netfilter: required for kube-proxy iptables mode
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
"
echo "$SYSCTL_CONTENT" > /etc/sysctl.d/99-kubernetes.conf
ok "Sysctl config written"

echo -e "  ${CYN}→${NC} Applying sysctl values..."
if sysctl --system; then
  ok "Sysctl values applied"
else
  warn "Some sysctl values may not have applied. Check: sysctl --system 2>&1 | grep -i error"
fi

# ---------- 4d: /etc/hosts peer entries ----------
echo ""
echo -e "  ${CYN}→${NC} Adding peer node entries to /etc/hosts..."

# Remove any previous entries we added (marked with a comment)
sed -i '/# Added by prepare-network.sh/,$d' /etc/hosts 2>/dev/null || true

{
  echo ""
  echo "# Added by prepare-network.sh — Kubernetes cluster peers"
  echo "${THIS_INT_IP}   ${THIS_HOSTNAME}"
  for peer in "${PEERS[@]}"; do
    pname="${peer%%:*}"
    pip="${peer##*:}"
    echo "${pip}   ${pname}"
  done
} >> /etc/hosts
ok "/etc/hosts updated with $((${#PEERS[@]} + 1)) entries"

# ---------- Verification ----------
echo ""
section "Post-Apply Verification"
echo ""
echo "  Verifying the new configuration took effect..."
echo ""

verify_local() {
  local label="$1"; local expected="$2"; local cmd="$3"
  local actual
  actual=$(eval "$cmd" 2>/dev/null || echo "(error)")
  if echo "$actual" | grep -q "$expected"; then
    ok "$label: $actual"
  else
    fail "$label: expected '${expected}', got '$actual'"
  fi
}

verify_local "eth0 IP"          "$THIS_INT_IP"  "ip -4 addr show eth0 | grep -oP 'inet \\K[\\d.]+' | head -1"
verify_local "eth1 IP"          "$THIS_EXT_IP"  "ip -4 addr show eth1 | grep -oP 'inet \\K[\\d.]+' | head -1"
verify_local "default route"    "via ${THIS_GATEWAY} dev eth1" "ip route show default | head -1"
verify_local "rp_filter all"    "= 1"  "sysctl -n net.ipv4.conf.all.rp_filter"
verify_local "rp_filter eth0"   "= 1"  "sysctl -n net.ipv4.conf.eth0.rp_filter"
verify_local "rp_filter eth1"   "= 1"  "sysctl -n net.ipv4.conf.eth1.rp_filter"
verify_local "ip_forward"       "= 1"  "sysctl -n net.ipv4.ip_forward"

# Ping test
if timeout 3 ping -c1 -W2 8.8.8.8 >/dev/null 2>&1; then
  ok "Internet reachable via eth1"
else
  fail "Internet NOT reachable — check eth1 configuration"
fi

# Peer reachability
for peer in "${PEERS[@]}"; do
  pname="${peer%%:*}"
  pip="${peer##*:}"
  if timeout 3 ping -c1 -W2 "$pip" >/dev/null 2>&1; then
    ok "Peer ${pname} (${pip}) reachable"
  else
    fail "Peer ${pname} (${pip}) UNREACHABLE"
  fi
done

# ---------- Summary ----------
section "Preparation Complete"
echo ""
echo "  ${BLD}Applied on ${THIS_HOSTNAME}:${NC}"
echo "    • Netplan: /etc/netplan/99-k8s.yaml"
echo "    • Sysctl:  /etc/sysctl.d/99-kubernetes.conf"
echo "    • Hosts:   $((${#PEERS[@]} + 1)) entries in /etc/hosts"
echo "    • Cloud-init: network management disabled"
echo ""
echo "  ${BLD}Next steps:${NC}"
echo "    1. Repeat this script on the other 2 nodes with their respective IPs."
echo "    2. From the control plane, run:  ./verify-network.sh"
echo ""
