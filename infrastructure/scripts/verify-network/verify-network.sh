#!/usr/bin/env bash
#
# verify-network.sh
# ============================================================================
#  Kubernetes Cluster Network Verification — Main Orchestrator
# ----------------------------------------------------------------------------
#  Validates the network configuration across all K8s cluster nodes BEFORE
#  kubeadm is installed.
#
#  Usage:
#    ./verify-network.sh                # Run all checks interactively
#    ./verify-network.sh --list         # List available checks
#    ./verify-network.sh --check <name> # Run a single check
#
#  Examples:
#    ./verify-network.sh --check dns-ssh
#    ./verify-network.sh --check connectivity
# ============================================================================

set -euo pipefail

# ---------- Resolve script directory (works even when symlinked) ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- Source library and check modules ----------
source "${SCRIPT_DIR}/lib/ui.sh"
source "${SCRIPT_DIR}/lib/ssh-utils.sh"
source "${SCRIPT_DIR}/collect-input.sh"
source "${SCRIPT_DIR}/check-dns-ssh.sh"
source "${SCRIPT_DIR}/check-node-config.sh"
source "${SCRIPT_DIR}/check-connectivity.sh"
source "${SCRIPT_DIR}/check-routes.sh"
source "${SCRIPT_DIR}/check-egress.sh"

# ---------- CLI argument parsing ----------
CHECK_ONLY=""
LIST_ONLY=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --list                 List all available checks and exit
  --check <name>         Run a single check (skips others)
  -h, --help             Show this help

Available checks:
  dns-ssh                Phase 1: DNS resolution and SSH reachability
  node-config            Phase 2: Per-node network configuration dump
  connectivity           Phase 3: Cross-node ICMP connectivity
  routes                 Phase 4: Default route placement
  egress                 Phase 5: Internet egress discipline

Examples:
  $(basename "$0")                  # Run the full verification
  $(basename "$0") --check egress   # Run only the egress check
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list)        LIST_ONLY=true; shift ;;
    --check)       CHECK_ONLY="$2"; shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    *)             echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

if $LIST_ONLY; then
  echo ""
  echo "Available checks:"
  echo "  dns-ssh      — Phase 1: DNS resolution and SSH reachability"
  echo "  node-config  — Phase 2: Per-node network configuration dump"
  echo "  connectivity — Phase 3: Cross-node ICMP connectivity"
  echo "  routes       — Phase 4: Default route placement"
  echo "  egress       — Phase 5: Internet egress discipline"
  echo ""
  exit 0
fi

# ---------- Welcome banner ----------
banner
echo "  This script will verify that the network on your K8s nodes is"
echo "  configured correctly before kubeadm is installed."
echo ""
if [[ -n "$CHECK_ONLY" ]]; then
  echo "  ${BLD}Mode:${NC} Running single check only: ${CYN}${CHECK_ONLY}${NC}"
  echo ""
fi
read -rp "  Press ENTER to begin, or Ctrl+C to exit: " _
echo ""

# ---------- Collect input (prompts only if variables are unset) ----------
collect_input

# ---------- Run selected check(s) ----------
case "$CHECK_ONLY" in
  ""|all)
    check_dns_ssh
    check_node_config
    check_connectivity
    check_routes
    check_egress
    print_summary
    ;;
  dns-ssh)      check_dns_ssh ;;
  node-config)  check_node_config ;;
  connectivity) check_connectivity ;;
  routes)       check_routes ;;
  egress)       check_egress ;;
  *)
    fail "Unknown check: '${CHECK_ONLY}'"
    echo ""
    usage
    exit 1
    ;;
esac


print_summary() {
  section "Verification Complete"
  echo ""
  echo "  ${BLD}What was checked:${NC}"
  echo "    ✓ DNS resolution for all nodes"
  echo "    ✓ SSH reachability to all nodes"
  echo "    ✓ Interface addressing on eth0 and eth1"
  echo "    ✓ Routing tables and default gateway placement"
  echo "    ✓ Cross-node ICMP over the internal network"
  echo "    ✓ Egress discipline (eth0 isolated, eth1 external)"
  echo ""
  echo "  ${BLD}Your cluster:${NC}"
  echo "    • Control plane: ${CTRL_NAME} (int ${CTRL_INT_IP}, ext ${CTRL_EXT_IP})"
  for i in "${!WORKER_NAMES[@]}"; do
    echo "    • Worker $((i+1)):      ${WORKER_NAMES[$i]} (int ${WORKER_INT_IPS[$i]}, ext ${WORKER_EXT_IPS[$i]})"
  done
  echo ""
  echo "  ${BLD}Internal subnet:${NC}  ${INTERNAL_SUBNET}.0/24"
  echo ""
  echo "  ${GRN}If all checks above are green ✓, you are ready to proceed${NC}"
  echo "  ${GRN}to Phase 1.2: kubeadm prerequisites and bootstrap.${NC}"
  echo ""
}
