# prepare-network/apply-cloud-init.sh
# ============================================================================
#  Masks cloud-init network management to prevent overwrites on reboot.
# ============================================================================

apply_cloud_init_mask() {
  echo ""
  echo -e "  ${CYN}→${NC} Masking cloud-init network configuration..."
  if ln -sf /dev/null /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg 2>/dev/null; then
    ok "Cloud-init network management disabled"
  else
    warn "Could not create cloud-init override (may not be present)"
  fi
}
