#!/usr/bin/env bash
#
# verify-network.sh (Assembled)
set -euo pipefail

# ---------- Resolve script directory ----------
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
  echo "Available checks: dns-ssh, node-config, connectivity, routes, egress"
  exit 0
fi

# ============================================================================
#  Function Definitions
# ============================================================================

print_summary() {
  section "Verification Complete"
  echo ""
  echo -e "  ${BLD}What was checked:${NC}"
  echo "    ✓ DNS resolution for all nodes"
  echo "    ✓ SSH reachability to all nodes"
  echo "    ✓ Interface addressing on eth0 and eth1"
  echo "    ✓ Routing tables and default gateway placement"
  echo "    ✓ Cross-node ICMP over the internal network"
  echo "    ✓ Egress discipline (eth0 isolated, eth1 external)"
  echo ""
  echo -e "  ${BLD}Your cluster:${NC}"
  echo -e "    • Control plane: ${CTRL_NAME} (int ${CTRL_INT_IP}, ext ${CTRL_EXT_IP})"
  for i in "${!WORKER_NAMES[@]}"; do
    echo -e "    • Worker $((i+1)):      ${WORKER_NAMES[$i]} (int ${WORKER_INT_IPS[$i]}, ext ${WORKER_EXT_IPS[$i]})"
  done
  echo ""
  echo -e "  ${BLD}Internal subnet:${NC}  ${INTERNAL_SUBNET}.0/24"
  echo ""
  echo -e "  ${GRN}If all checks above are green ✓, you are ready to proceed${NC}"
  echo -e "  ${GRN}to Phase 1.2: kubeadm prerequisites and bootstrap.${NC}"
  echo ""
}

# ============================================================================
#  Main Execution Logic
# ============================================================================

# ---------- Welcome banner ----------
banner
echo "  This script will verify that the network on your K8s nodes is"
echo "  configured correctly before kubeadm is installed."
echo ""
if [[ -n "$CHECK_ONLY" ]]; then
  echo -e "  ${BLD}Mode:${NC} Running single check only: ${CYN}${CHECK_ONLY}${NC}"
  echo ""
fi
read -rp "  Press ENTER to begin, or Ctrl+C to exit: " _
echo ""

# ---------- Collect input ----------
collect_input

# ---------- Run selected check(s) ----------
case "$CHECK_ONLY" in
  ""|all)
    check_dns_ssh
    check_node_config
    check_connectivity
    check_routes
    check_egress
    print_summary  # <--- This will now execute cleanly
    ;;
  dns-ssh)      check_dns_ssh ;;
  node-config)  check_node_config ;;
  connectivity) check_connectivity ;;
  routes)       check_routes ;;
  egress)       check_egress ;;
  *)
    fail "Unknown check: '${CHECK_ONLY}'"
    usage
    exit 1
    ;;
esac
