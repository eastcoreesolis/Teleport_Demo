# kubeadm-install/01-prerequisites.sh
# Phase 1: Prepare the host OS for Kubernetes

source "${SCRIPT_DIR}/lib/version-pinning.sh"

install_prerequisites() {
  section "Phase 1 of 4 — Host OS Prerequisites"
  echo ""
  echo -e "  ${CYN}→${NC} Updating apt package lists..."
  apt-get update -y >/dev/null

  echo -e "  ${CYN}→${NC} Installing base dependencies (apt-transport-https, curl, etc.)..."
  apt-get install -y apt-transport-https ca-certificates curl gpg software-properties-common >/dev/null
  
  ok "Base dependencies installed"
  
  echo ""
  echo -e "  ${CYN}→${NC} Disabling swap (required by Kubernetes)..."
  swapoff -a
  
  # Ensure swap stays off after reboot by commenting out fstab entries
  if grep -qE "^\S+\s+\S+\s+swap" /etc/fstab; then
    sed -i '/\sswap\s/s/^/#/' /etc/fstab
    ok "Swap disabled and /etc/fstab updated"
  else
    ok "Swap was not active or already disabled"
  fi
}
