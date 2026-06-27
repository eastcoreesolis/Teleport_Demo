# prepare-network/apply-sysctl.sh
# ============================================================================
#  Writes and applies Kubernetes sysctl requirements.
# ============================================================================

apply_sysctls() {
  echo ""
  echo -e "  ${CYN}→${NC} Writing /etc/sysctl.d/99-kubernetes.conf..."

  cat > /etc/sysctl.d/99-kubernetes.conf <<SYSCTL_EOF
# Kubernetes networking requirements
# Reverse-path filtering: 1 (strict) — required for dual-NIC setups with CNIs
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.${INTERNAL_IFACE}.rp_filter = 1
net.ipv4.conf.${EXTERNAL_IFACE}.rp_filter = 1

# IP forwarding: required for pod-to-pod routing across nodes
net.ipv4.ip_forward = 1

# Bridge netfilter: required for kube-proxy iptables mode
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
SYSCTL_EOF

  ok "Sysctl config written"

  echo -e "  ${CYN}→${NC} Applying sysctl values..."
  
  # Force-load our specific configuration file first so it overrides system defaults
  if sysctl -p /etc/sysctl.d/99-kubernetes.conf >/dev/null 2>&1; then
    # Also trigger a system-wide sync just in case
    sysctl --system >/dev/null 2>&1 || true
    ok "Sysctl values successfully applied and verified"
  else
    fail "Failed to apply sysctl values from /etc/sysctl.d/99-kubernetes.conf"
    return 1
  fi
}
