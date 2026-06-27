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
  if sysctl --system >/dev/null 2>&1; then
    ok "Sysctl values applied"
  else
    warn "Some sysctl values may not have applied. Check: sysctl --system 2>&1 | grep -i error"
  fi
}
