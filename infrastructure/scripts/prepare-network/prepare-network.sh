#!/usr/bin/env bash
#
# prepare-network.sh — Main Orchestrator
# ============================================================================
#  Prepares a single K8s node's network configuration for cluster use.
#  Run this on EACH of the 3 nodes before verify-network.sh.
#
#  Usage:
#    sudo ./prepare-network.sh
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_LIB="${SCRIPT_DIR}/../lib"

# ---------- Source shared libraries ----------
source "${SHARED_LIB}/ui.sh"
source "${SHARED_LIB}/net-utils.sh"

# ---------- Source modules ----------
source "${SCRIPT_DIR}/lib/topology.sh"
source "${SCRIPT_DIR}/collect-config.sh"
source "${SCRIPT_DIR}/apply-netplan.sh"
source "${SCRIPT_DIR}/apply-cloud-init.sh"
source "${SCRIPT_DIR}/apply-sysctl.sh"
source "${SCRIPT_DIR}/apply-hosts.sh"
source "${SCRIPT_DIR}/verify-local.sh"

# ---------- Root check ----------
if [[ $EUID -ne 0 ]]; then
  fail "This script must be run as root (use: sudo ./prepare-network.sh)"
  exit 1
fi

# ---------- Welcome ----------
banner
echo "  This script prepares a single K8s node's network configuration."
echo "  It has auto-detected your node's identity. Press ENTER at each"
echo "  prompt to accept the pre-calculated defaults."
echo ""

# ---------- Auto-detect topology ----------
auto_detect_role
detect_iface

export INTERNAL_IFACE
export EXTERNAL_IFACE

echo ""
read -rp "  Press ENTER to begin, or Ctrl+C to exit: " _
echo ""

# ---------- Step 1 & 2: Collect configuration ----------
collect_node_config
collect_peer_nodes

export THIS_INT_IP
export THIS_EXT_IP
export THIS_GATEWAY

# ---------- Step 3 & 4: Apply changes ----------
echo ""
echo "  Applying the following changes:"
echo "    • Netplan configuration (${INTERNAL_IFACE}/${EXTERNAL_IFACE})"
echo "    • Sysctl values (rp_filter, IP forwarding)"
echo "    • Cloud-init network mask"
echo "    • /etc/hosts entries for peer nodes"
echo ""
read -rp "  Press ENTER to apply, or Ctrl+C to cancel: " _
echo ""

apply_netplan
apply_cloud_init_mask
apply_sysctls
apply_hosts

# ---------- Verify ----------
#verify_local_config

set +e
set +o pipefail

verify_local_config

# Restore strict checks
set -e
set -o pipefail


# ---------- Summary ----------
section "Preparation Complete"
echo ""
echo -e "  ${BLD}Applied on ${THIS_HOSTNAME}:${NC}"
echo "    • Netplan: /etc/netplan/99-k8s.yaml"
echo "    • Sysctl:  /etc/sysctl.d/99-kubernetes.conf"
echo "    • Hosts:   $((${#PEERS[@]} + 1)) entries in /etc/hosts"
echo "    • Cloud-init: network management disabled"
echo ""
echo -e "  ${BLD}Next steps:${NC}"
echo "    1. Repeat this script on the other 2 nodes."
echo "    2. From the control plane, run:  ./verify-network.sh"
echo ""
