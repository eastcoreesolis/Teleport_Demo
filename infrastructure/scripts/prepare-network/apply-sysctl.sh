# prepare-network/apply-sysctl.sh
# ============================================================================
#  Writes and applies Kubernetes sysctl requirements.
# ============================================================================

apply_sysctls() {
  section "Step 4.2 of 4.3 - sysctl.d configuration"
  echo ""
  echo -e "  ${CYN}→${NC} Loading bridge network kernel modules..."
  # Load br_netfilter so the kernel compiles net.bridge system paths
  if modprobe br_netfilter 2>/dev/null; then
    echo "br_netfilter" > /etc/modules-load.d/k8s.conf
    ok "br_netfilter module loaded and configured to persist on reboot"
  else
    warn "Could not load br_netfilter module. If this is a VM, you may need to enable nesting/virtualization."
  fi

  echo -e "  ${CYN}→${NC} Writing /etc/sysctl.d/99-kubernetes.conf..."

  cat > /etc/sysctl.d/99-kubernetes.conf <<SYSCTL_EOF
# Kubernetes networking requirements
# Reverse-path filtering: 1 (strict) — required for dual-NIC setups with CNIs
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.${INTERNAL_IFACE}.rp_filter = 2
net.ipv4.conf.${EXTERNAL_IFACE}.rp_filter = 2

# IP forwarding: required for pod-to-pod routing across nodes
net.ipv4.ip_forward = 1

# Bridge netfilter: required for kube-proxy iptables mode
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
SYSCTL_EOF

  ok "Sysctl config written"

  echo -e "  ${CYN}→${NC} Applying sysctl values..."

  # Direct-apply configuration file
  if sysctl -p /etc/sysctl.d/99-kubernetes.conf >/dev/null 2>&1; then
    # Sync system configuration
    sysctl --system >/dev/null 2>&1 || true
    ok "Sysctl values successfully applied and verified"
  else
    fail "Failed to apply sysctl values from /etc/sysctl.d/99-kubernetes.conf"
    return 1
  fi
}
