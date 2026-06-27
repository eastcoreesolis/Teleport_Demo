#!/usr/bin/env bash
#
# bootstrap-control-plane.sh
# ============================================================================
#  Post-init script to configure local kubectl context and install Calico.
#  Run this AFTER successfully running 'kubeadm init'.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_LIB="${SCRIPT_DIR}/../lib"

source "${SHARED_LIB}/ui.sh"
source "${SCRIPT_DIR}/05-install-calico.sh"

banner
echo "  This script configures kubectl and deploys the Calico CNI."
echo ""

# ---------- 1. Configure Kubeconfig ----------
section "Phase 1: Local Kubectl Configuration"
echo ""
if [[ ! -f /etc/kubernetes/admin.conf ]]; then
  fail "Could not find /etc/kubernetes/admin.conf."
  echo "      Did you run 'sudo kubeadm init' first?"
  exit 1
fi

echo -e "  ${CYN}→${NC} Setting up ~/.kube/config for user ${USER}..."
mkdir -p "$HOME/.kube"
sudo cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
ok "Kubectl configuration written successfully"

# ---------- 2. Install Calico ----------
install_calico

# ---------- 3. Print Worker Join Instructions ----------
section "Control Plane Active"
echo ""
echo -e "  ${GRN}✓${NC} Your control plane is fully configured and ready."
echo ""
echo "  To join your worker nodes to this cluster:"
echo "    1. Configure the worker's Kubelet to use its internal IP address:"
echo -e "       ${BLD}echo 'KUBELET_EXTRA_ARGS=\"--node-ip=<worker-internal-ip>\"' | sudo tee /etc/default/kubelet${NC}"
echo "    2. Execute the exact, token-authenticated 'kubeadm join' command"
echo "       printed in the terminal output of your control-plane's 'kubeadm init' run."
echo ""
