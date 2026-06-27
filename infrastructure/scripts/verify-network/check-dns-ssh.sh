# check-dns-ssh.sh
# ============================================================================
#  Phase 1 — DNS Resolution and SSH Reachability
# ============================================================================

check_dns_ssh() {
  section "Phase 1 of 5 — DNS Resolution & SSH Reachability"
  echo ""
  echo "  Checking that each node's hostname resolves via DNS (IPv4),"
  echo "  and that we can SSH to it without a password."
  echo ""

  local dns_failed=false
  local ssh_failed=false

  for i in "${!ALL_NAMES[@]}"; do
    local h="${ALL_NAMES[$i]}"
    local ip="${ALL_EXT_IPS[$i]}"
    echo -e "  ${BLD}Checking ${h}...${NC}"

    local dns_result
    dns_result=$(nslookup -query=A "$h" 2>&1 | grep -A1 "^Name:" | tail -1 | awk '{print $2}' || true)
    if [[ -z "$dns_result" || "$dns_result" == *"can't"* ]]; then
      dns_result=$(grep -iE "[[:space:]]${h}([[:space:]]|$)" /etc/hosts | awk '{print $1}' | head -n 1 || true)
    fi

    if [[ "$dns_result" == "$ip" ]]; then
      ok "DNS resolves ${h} → ${ip}"
    else
      warn "DNS for ${h} does not match expected ${ip} (got: '${dns_result:-NXDOMAIN}')"
      note "We can still proceed if SSH works, but internal cluster apps may need DNS fixed later."
      dns_failed=true
    fi

    if run_on_host "$ip" true >/dev/null 2>&1; then
      ok "SSH to ${h} (${ip}) works"
    else
      fail "Cannot SSH to ${h} (${ip})"
      note "Hint: run 'ssh-copy-id ${SSH_USER}@${ip}' to install your public key"
      ssh_failed=true
    fi
    echo ""
  done

  if $ssh_failed; then
    echo ""
    fail "SSH reachability failed for one or more nodes. Cannot continue."
    echo "  Please run 'ssh-copy-id' for the failing nodes and try again."
    exit 1
  fi

  if $dns_failed; then
    echo ""
    warn "Some hostname DNS resolutions failed (shown above)."
    echo "  Because passwordless SSH to all nodes is verified, we can continue."
    read -rp "  Press ENTER to bypass DNS warnings and proceed, or Ctrl+C to exit: " _
    echo ""
  fi

  ok "All nodes reachable via SSH. Proceeding..."
}

