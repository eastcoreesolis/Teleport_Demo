# prepare-network/apply-hosts.sh
# ============================================================================
#  Adds peer node entries to /etc/hosts for static DNS resolution.
# ============================================================================

apply_hosts() {
  section "Step 4.3 of 4.3 - hosts file configuration"
  echo ""
  echo -e "  ${CYN}→${NC} Adding peer node entries to /etc/hosts..."

  # Remove any previous entries we added
  sed -i '/# Added by prepare-network.sh/,$d' /etc/hosts 2>/dev/null || true

  {
    echo ""
    echo "# Added by prepare-network.sh — Kubernetes cluster peers"
    echo "${THIS_INT_IP}   ${THIS_HOSTNAME}"
    for peer in "${PEERS[@]}"; do
      local pname="${peer%%:*}"
      local pip="${peer##*:}"
      echo "${pip}   ${pname}"
    done
  } >> /etc/hosts

  ok "/etc/hosts updated with $((${#PEERS[@]} + 1)) entries"
}
