#!/usr/bin/env bash
#
# kubeadm-install.sh — Main Orchestrator
# ============================================================================
#  Installs containerd and Kubernetes components on Ubuntu 22.04 LTS.
#  Run this on EACH of the 3 nodes.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_LIB="${SCRIPT_DIR}/../lib"

# ---------- Source shared UI utilities ----------
source "${SHARED_LIB}/ui.sh"

# ---------- Source installation modules ----------
source "${SCRIPT_DIR}/01-prerequisites.sh"
source "${SCRIPT_DIR}/02-containerd.sh"
source "${SCRIPT_DIR}/03-kubetools.sh"
source "${SCRIPT_DIR}/04-verify-prereqs.sh"

# ---------- Root Check ----------
if [[ $EUID -ne 0 ]]; then
  fail "This script must be run as root (use: sudo ./kubeadm-install.sh)"
  exit 1
fi

# ---------- Welcome Banner ----------
banner
echo -e "  This script will prepare your ${BLD}Ubuntu 22.04${NC} machine and install"
echo "  containerd, kubeadm, kubelet, and kubectl pinned to stable versions."
echo ""
read -rp "  Press ENTER to begin, or Ctrl+C to cancel: " _
echo ""

# Execute installation sequence
install_prerequisites
install_containerd
install_kubetools
verify_prereqs

# ---------- Completion Summary ----------
section "System Installation Complete"
echo ""
echo -e "  ${BLD}Installed on $(hostname):${NC}"
echo "    • containerd: configured for systemd cgroup driver"
echo "    • kubeadm:    ready for cluster bootstrap"
echo "    • kubelet:    enabled and will start on first init/join"
echo ""
echo -e "  ${BLD}Next steps:${NC}"
echo "    1. Repeat this script on your other cluster nodes."
echo "    2. On this control plane, initialize the cluster:"
echo "         sudo kubeadm init --apiserver-advertise-address=192.168.2.85 --pod-network-cidr=192.168.0.0/16 --node-name=kcontrolplane"
echo "    3. Deploy the CNI using the bootstrap runner."
echo ""
