# kubeadm-install/01-prerequisites.sh
# ============================================================================
#  Phase 1: Prepare the host OS for Kubernetes
# ============================================================================

install_prerequisites() {
  section "Phase 1 of 4 — Host OS Prerequisites"
  echo ""
  echo -e "  ${CYN}→${NC} Updating APT package lists..."
  apt-get update -y >/dev/null

  echo -e "  ${CYN}→${NC} Installing system base dependencies..."
  apt-get install -y apt-transport-https ca-certificates curl gpg software-properties-common >/dev/null
  ok "Base dependencies installed"

  echo ""
  echo -e "  ${CYN}→${NC} Disabling swap immediately..."
  swapoff -a

  # Ensure swap remains disabled on boot by commenting out fstab entries
  if grep -qE "^\S+\s+\S+\s+swap" /etc/fstab; then
    sed -i '/\sswap\s/s/^/#/' /etc/fstab
    ok "Swap disabled and /etc/fstab updated"
  else
    ok "Swap is already disabled in /etc/fstab"
  fi

  echo ""
  echo -e "  ${CYN}→${NC} Enabling kernel routing modules..."
  # Load modules immediately
  modprobe overlay
  modprobe br_netfilter

  # Persist modules across system reboots
  cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
  ok "Kernel modules (overlay, br_netfilter) loaded and persisted"
}
