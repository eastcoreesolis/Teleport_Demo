#!/usr/bin/env bash
#
# prepare-network.sh
# ============================================================================
#  Prepares a single K8s node's network configuration for cluster use.
# ----------------------------------------------------------------------------
#  This script MUST be run on EACH of the 3 nodes before verify-network.sh
#  is run from the control plane.
#
#  Features:
#    • Auto-detects node role based on hostname
#    • Automatically calculates matching default IPs, gateways, and DNS
#    • Dynamically detects actual interface names (eth0/enp0s3/etc.)
#    • Uses heredoc for netplan generation (bulletproof YAML)
#    • Allows complete pass-through configuration by pressing ENTER
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

# ---------- Auto-Detect Topology Defaults ----------
CURRENT_HOSTNAME=$(hostname)
DEFAULT_GATEWAY="192.168.1.254"
DEFAULT_DNS="192.168.1.70,192.168.1.254"
DEFAULT_SEARCH="eastcore.local"

# Calculate contextual defaults based on hostname
if [[ "$CURRENT_HOSTNAME" =~ (control|master) ]]; then
  DEFAULT_THIS_HOSTNAME="kcontrolplane"
  DEFAULT_INT_IP="192.168.2.85"
  DEFAULT_EXT_IP="192.168.1.85"
  DEFAULT_PEER_NAMES=("kworkera" "kworkerb")
  DEFAULT_PEER_IPS=("192.168.2.86" "192.168.2.87")
elif [[ "$CURRENT_HOSTNAME" =~ (workera|worker1|worker-a) ]]; then
  DEFAULT_THIS_HOSTNAME="kworkera"
  DEFAULT_INT_IP="192.168.2.86"
  DEFAULT_EXT_IP="192.168.1.86"
  DEFAULT_PEER_NAMES=("kcontrolplane" "kworkerb")
  DEFAULT_PEER_IPS=("192.168.2.85" "192.168.2.87")
elif [[ "$CURRENT_HOSTNAME" =~ (workerb|worker2|worker-b) ]]; then
  DEFAULT_THIS_HOSTNAME="kworkerb"
  DEFAULT_INT_IP="192.168.2.87"
  DEFAULT_EXT_IP="192.168.1.87"
  DEFAULT_PEER_NAMES=("kcontrolplane" "kworkera")
  DEFAULT_PEER_IPS=("192.168.2.85" "192.168.2.86")
else
  # Generic fallbacks if hostname is completely custom
  DEFAULT_THIS_HOSTNAME="$CURRENT_HOSTNAME"
  DEFAULT_INT_IP="192.168.2.85"
  DEFAULT_EXT_IP="192.168.1.85"
  DEFAULT_PEER_NAMES=("kworkera" "kworkerb")
  DEFAULT_PEER_IPS=("192.168.2.86" "192.168.2.87")
fi

# ---------- Auto-Detect Interface Names ----------
detect_iface() {
  local role="$1"
  local iface
  if [[ "$role" == "internal" ]]; then
    iface=$(ls /sys/class/net/ | grep -v "lo" | head -1)
  else
    iface=$(ls /sys/class/net/ | grep -v "lo" | sed -n '2p')
  fi
  echo "$iface"
}

INTERNAL_IFACE=$(detect_iface "internal")
EXTERNAL_IFACE=$(detect_iface "external")

# ---------- Welcome ----------
banner
echo "  This script prepares a single K8s node's network configuration."
echo "  It has auto-detected your node's identity and loaded standard defaults."
echo "  If you are following the reference design, simply press ENTER at"
echo "  each prompt to accept the pre-calculated default values."
echo ""
echo -e "  ${BLD}Detected Hostname:${NC}    ${CURRENT_HOSTNAME}"
echo -e "  ${BLD}Assigned Role:${NC}        ${DEFAULT_THIS_HOSTNAME}"
echo -e "  ${BLD}Internal Interface:${NC}   ${INTERNAL_IFACE}"
echo -e "  ${BLD}External Interface:${NC}   ${EXTERNAL_IFACE}"
echo ""
read -rp "  Press ENTER to begin, or Ctrl+C to exit: " _
echo ""

# ---------- Step 1: Node role and IP configuration ----------
section "Step 1 of 4 — Node Identity and IP Configuration"
echo ""

# Hostname
read -rp "  This node's hostname [${DEFAULT_THIS_HOSTNAME}]: " THIS_HOSTNAME
THIS_HOSTNAME=${THIS_HOSTNAME:-$DEFAULT_THIS_HOSTNAME}
ok "Hostname: ${BLD}${THIS_HOSTNAME}${NC}"

# Internal IP
while true; do
  read -rp "  INTERNAL IP (${INTERNAL_IFACE}) [${DEFAULT_INT_IP}]: " THIS_INT_IP
  THIS_INT_IP=${THIS_INT_IP:-$DEFAULT_INT_IP}
  if is_valid_ip "$THIS_INT_IP"; then
    break
  else
    fail "'${THIS_INT_IP}' is not a valid IPv4 address. Please try again."
  fi
done
ok "Internal IP: ${BLD}${THIS_INT_IP}${NC}"

# External IP
while true; do
  read -rp "  EXTERNAL IP (${EXTERNAL_IFACE}) [${DEFAULT_EXT_IP}]: " THIS_EXT_IP
  THIS_EXT_IP=${THIS_EXT_IP:-$DEFAULT_EXT_IP}
  if is_valid_ip "$THIS_EXT_IP"; then
    break
  else
    fail "'${THIS_EXT_IP}' is not a valid IPv4 address. Please try again."
  fi
done
ok "External IP: ${BLD}${THIS_EXT_IP}${NC}"

# Default gateway (for external interface)
while true; do
  read -rp "  External default gateway [${DEFAULT_GATEWAY}]: " THIS_GATEWAY
  THIS_GATEWAY=${THIS_GATEWAY:-$DEFAULT_GATEWAY}
  if is_valid_ip "$THIS_GATEWAY"; then
    break
  else
    fail "'${THIS_GATEWAY}' is not a valid IPv4 address. Please try again."
  fi
done
ok "Default gateway: ${BLD}${THIS_GATEWAY}${NC}"

# DNS servers
read -rp "  DNS servers [${DEFAULT_DNS}]: " THIS_DNS
THIS_DNS=${THIS_DNS:-$DEFAULT_DNS}
ok "DNS servers: ${BLD}${THIS_DNS}${NC}"

# Search domain
read -rp "  DNS search domain [${DEFAULT_SEARCH}]: " THIS_SEARCH
THIS_SEARCH=${THIS_SEARCH:-$DEFAULT_SEARCH}
if [[ -n "$THIS_SEARCH" ]]; then
  ok "Search domain: ${BLD}${THIS_SEARCH}${NC}"
else
  ok "Search domain: (none)"
fi

# ---------- Step 2: Peer nodes (for /etc/hosts) ----------
section "Step 2 of 4 — Peer Cluster Nodes"
echo ""
echo "  Confirm the hostname and internal IPs of the other cluster nodes."
echo "  These will be added to /etc/hosts for static resolution."
echo ""

PEERS=()
read -rp "  How many peer nodes? [2]: " PEER_COUNT_INPUT
PEER_COUNT=${PEER_COUNT_INPUT:-2}

for ((i=0; i<PEER_COUNT; i++)); do
  # Pull dynamic defaults if they exist
  default_pname="${DEFAULT_PEER_NAMES[$i]:-kworker}"
  default_pip="${DEFAULT_PEER_IPS[$i]:-192.168.2.$((86 + i))}"

  echo -e "  ${BLD}--- Peer $((i+1)) of $PEER_COUNT ---${NC}"

  read -rp "    Hostname [${default_pname}]: " pname
  pname=${pname:-$default_pname}

  while true; do
    read -rp "    Internal IP [${default_pip}]: " pip
    pip=${pip:-$default_pip}
    is_valid_ip "$pip" && break
    fail "Invalid IPv4 address. Please try again."
  done

  PEERS+=("${pname}:${pip}")
  ok "Peer $((i+1)): ${BLD}${pname}${NC} (${pip})"
  echo ""
done

# ---------- Step 3: Netplan ----------
section "Step 3 of 4 — Netplan Configuration"
echo ""
echo "  The following netplan will be written to /etc/netplan/99-k8s.yaml:"
echo ""

# Build DNS list with correct indentation
DNS_LINES=""
IFS=',' read -ra DNS_ARRAY <<< "$THIS_DNS"
for d in "${DNS_ARRAY[@]}"; do
  DNS_LINES="${DNS_LINES}          - ${d}
"
done

# Build search block with correct indentation
if [[ -n "$THIS_SEARCH" ]]; then
  SEARCH_BLOCK="          search:
            - ${THIS_SEARCH}
"
else
  SEARCH_BLOCK=""
fi

echo -e "${CYN}──── /etc/netplan/99-k8s.yaml ────────────────────────────────${NC}"
cat <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${INTERNAL_IFACE}:
      dhcp4: no
      dhcp6: no
      optional: true
      addresses:
        - ${THIS_INT_IP}/24
    ${EXTERNAL_IFACE}:
      dhcp4: no
      dhcp6: no
      optional: true
      addresses:
        - ${THIS_EXT_IP}/24
      routes:
        - to: default
          via: ${THIS_GATEWAY}
          metric: 100
      nameservers:
        addresses:
${DNS_LINES}${SEARCH_BLOCK}EOF
echo -e "${CYN}──────────────────────────────────────────────────────────────${NC}"
echo ""
read -rp "  Apply this netplan? [Y/n]: " confirm_netplan
confirm_netplan=${confirm_netplan:-Y}
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
[[ "$APPLY_NETPLAN" == "true" ]] && echo "    • Netplan configuration (${INTERNAL_IFACE}/${EXTERNAL_IFACE})"
echo "    • Sysctl values (rp_filter, IP forwarding)"
echo "    • Cloud-init network mask"
echo "    • /etc/hosts entries for peer nodes"
echo ""
read -rp "  Press ENTER to apply, or Ctrl+C to cancel: " _
echo ""

# ---------- 4a: Netplan ----------
if [[ "$APPLY_NETPLAN" == "true" ]]; then
  echo -e "  ${CYN}→${NC} Writing /etc/netplan/99-k8s.yaml..."

  cat > /etc/netplan/99-k8s.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${INTERNAL_IFACE}:
      dhcp4: no
      dhcp6: no
      optional: true
      addresses:
        - ${THIS_INT_IP}/24
    ${EXTERNAL_IFACE}:
      dhcp4: no
      dhcp6: no
      optional: true
      addresses:
        - ${THIS_EXT_IP}/24
      routes:
        - to: default
          via: ${THIS_GATEWAY}
          metric: 100
      nameservers:
        addresses:
${DNS_LINES}${SEARCH_BLOCK}EOF

  chmod 600 /etc/netplan/99-k8s.yaml

  # Remove conflicting default configs
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
    echo ""
    echo "  ${YLW}Current netplan files:${NC}"
    ls -la /etc/netplan/
    echo ""
    echo "  ${YLW}Contents of 99-k8s.yaml:${NC}"
    cat /etc/netplan/99-k8s.yaml
    exit 1
  fi
else
  warn "Netplan NOT applied. Manual configuration required."
fi

# ---------- 4b: Cloud-init mask ----------
echo ""
echo -e "  ${CYN}→${NC} Masking cloud-init network configuration..."
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
net.ipv4.conf.${INTERNAL_IFACE}.rp_filter = 1
net.ipv4.conf.${EXTERNAL_IFACE}.rp_filter = 1

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

verify_interface_ip() {
  local iface="$1"; local expected="$2"
  local actual
  actual=$(ip -4 -o addr show "$iface" 2>/dev/null | grep 'inet ' | awk '{print $4}' | cut -d/ -f1 | head -1)
  if [[ "$actual" == "$expected" ]]; then
    ok "${iface} IP: $actual"
  else
    fail "${iface} IP: expected '${expected}', got '${actual:-EMPTY}'"
  fi
}

verify_default_route() {
  local expected_gw="$1"; local expected_iface="$2"
  local actual
  actual=$(ip route show default 2>/dev/null | head -1)
  if echo "$actual" | grep -qF "via ${expected_gw} dev ${expected_iface}"; then
    ok "default route: $actual"
  else
    fail "default route: expected 'via ${expected_gw} dev ${expected_iface}', got '${actual:-EMPTY}'"
  fi
}

verify_sysctl() {
  local key="$1"; local expected="$2"
  local actual
  actual=$(sysctl -n "$key" 2>/dev/null)
  if [[ "$actual" == "$expected" ]]; then
    ok "${key}: $actual"
  else
    fail "${key}: expected '${expected}', got '${actual:-EMPTY}'"
  fi
}

# Run verifications with auto-detected interface names
verify_interface_ip "$INTERNAL_IFACE" "$THIS_INT_IP"
verify_interface_ip "$EXTERNAL_IFACE" "$THIS_EXT_IP"
verify_default_route "$THIS_GATEWAY" "$EXTERNAL_IFACE"
verify_sysctl "net.ipv4.conf.all.rp_filter"  "1"
verify_sysctl "net.ipv4.conf.${INTERNAL_IFACE}.rp_filter" "1"
verify_sysctl "net.ipv4.conf.${EXTERNAL_IFACE}.rp_filter" "1"
verify_sysctl "net.ipv4.ip_forward"          "1"

# Ping test
if timeout 3 ping -c1 -W2 8.8.8.8 >/dev/null 2>&1; then
  ok "Internet reachable via ${EXTERNAL_IFACE}"
else
  fail "Internet NOT reachable — check ${EXTERNAL_IFACE} configuration"
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
