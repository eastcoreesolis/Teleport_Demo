#!/usr/bin/env bash
#
# kubeadm-install.sh — Main Orchestrator
# ============================================================================
#  Installs containerd and Kubernetes components (kubeadm, kubelet, kubectl).
#  Run this on EACH of the 3 nodes before 'kubeadm init'.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_LIB="${SCRIPT_DIR}/../lib"

# ---------- Source shared libraries ----------
source "${SHARED_LIB}/ui.sh"

# ---------- Source local modules ----------
source "${SCRIPT_DIR}/01-prerequisites.sh"
source "${SCRIPT_DIR}/02-containerd.sh"
source "${SCRIPT_DIR}/03-kubetools.sh"
source "${SCRIPT_DIR}/04-verify-prereqs.sh"

# ---------- Root check ----------
if [[ $EUID -ne 0 ]]; then
  fail "This script must be run as root (use: sudo ./kubeadm-install.sh)"
  exit 1
fi

# ---------- Welcome ----------
banner
echo "  This script will install containerd, kubeadm, kubelet, and kubectl."
echo "  Press ENTER at each prompt to accept the default versions."
echo ""

# Run all installation phases sequentially
install_prerequisites
install_containerd
install_kubetools
verify_prereqs

# ---------- Summary ----------
section "Installation Complete"
echo ""
echo -e "  ${BLD}Installed on $(hostname):${NC}"
echo "    • containerd: configured for systemd cgroup driver"
echo "    • kubeadm:    ready for cluster bootstrap"
echo "    • kubelet:    enabled and will start on first init/join"
echo ""
echo -e "  ${BLD}Next steps:${NC}"
echo "    1. Repeat this script on the other 2 nodes."
echo "    2. From the control plane, run:  sudo kubeadm init ..."
echo ""
