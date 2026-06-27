# prepare-network/verify-local.sh
# ============================================================================
#  Post-apply verification: confirms the configuration took effect.
# ============================================================================

TMP_IP_FILE=$(mktemp /tmp/verify_ip.XXXXXX)
TMP_ROUTE_FILE=$(mktemp /tmp/verify_route.XXXXXX)

# Safely query an interface IP using a file redirect instead of pipes
get_interface_ip() {
  local iface="$1"
  # Use a fresh redirect instead of pipes. Redirects do not trigger SIGPIPE.
  ip -4 addr show dev "$iface" 2>/dev/null > "$TMP_IP_FILE" || true

  # Process the file
  awk '/inet / {print $2}' "$TMP_IP_FILE" | cut -d/ -f1 | head -n1
}

# Safely query the default route using a file redirect
get_default_route() {
  ip route show default 2>/dev/null > "$TMP_ROUTE_FILE" || true
  head -n1 "$TMP_ROUTE_FILE"
}

# Cleanup on exit
cleanup_tmp_files() {
  rm -f "$TMP_IP_FILE" "$TMP_ROUTE_FILE"
}
trap cleanup_tmp_files EXIT

wait_for_network() {
  echo ""
  echo -e "  ${CYN}→${NC} Waiting for network to converge (up to 15 seconds)..."

  local waited=0
  local int_ip=""
  local ext_ip=""

  while (( waited < 15 )); do
    int_ip=$(get_interface_ip "$INTERNAL_IFACE")
    ext_ip=$(get_interface_ip "$EXTERNAL_IFACE")

    if [[ -n "$int_ip" && -n "$ext_ip" ]]; then
      ok "Network interfaces are up (Internal: $int_ip, External: $ext_ip)"
      sleep 2  # Let routing table settle fully
      return 0
    fi
    sleep 1
    ((waited++))
  done
  warn "Network did not fully converge within 15 seconds. Continuing checks anyway."
}

verify_local_config() {
  section "Post-Apply Verification"
  wait_for_network
  echo ""
  echo "  Verifying the new configuration took effect..."
  echo ""

  # 1. Verify Internal Interface IP
  local int_actual=""
  int_actual=$(get_interface_ip "$INTERNAL_IFACE")
  if [[ "$int_actual" == "$THIS_INT_IP" ]]; then
    ok "${INTERNAL_IFACE} IP: $int_actual"
  else
    fail "${INTERNAL_IFACE} IP: expected '${THIS_INT_IP}', got '${int_actual:-EMPTY}'"
  fi

  # 2. Verify External Interface IP
  local ext_actual=""
  ext_actual=$(get_interface_ip "$EXTERNAL_IFACE")
  if [[ "$ext_actual" == "$THIS_EXT_IP" ]]; then
    ok "${EXTERNAL_IFACE} IP: $ext_actual"
  else
    fail "${EXTERNAL_IFACE} IP: expected '${THIS_EXT_IP}', got '${ext_actual:-EMPTY}'"
  fi

  # 3. Verify Default Route
  local route_actual=""
  route_actual=$(get_default_route)
  if echo "$route_actual" | grep -qF "via ${THIS_GATEWAY} dev ${EXTERNAL_IFACE}"; then
    ok "default route: $route_actual"
  else
    fail "default route: expected 'via ${THIS_GATEWAY} dev ${EXTERNAL_IFACE}', got '${route_actual:-EMPTY}'"
  fi

  # 4. Verify Sysctl settings
  local rp_all="" rp_int="" rp_ext="" ip_fwd=""

  rp_all=$(sysctl -n net.ipv4.conf.all.rp_filter 2>/dev/null || echo "0")
  [[ "$rp_all" == "1" ]] && ok "net.ipv4.conf.all.rp_filter: $rp_all" || fail "rp_filter all: got '${rp_all:-EMPTY}'"

  rp_int=$(sysctl -n "net.ipv4.conf.${INTERNAL_IFACE}.rp_filter" 2>/dev/null || echo "0")
  [[ "$rp_int" == "1" ]] && ok "net.ipv4.conf.${INTERNAL_IFACE}.rp_filter: $rp_int" || fail "rp_filter ${INTERNAL_IFACE}: got '${rp_int:-EMPTY}'"

  rp_ext=$(sysctl -n "net.ipv4.conf.${EXTERNAL_IFACE}.rp_filter" 2>/dev/null || echo "0")
  [[ "$rp_ext" == "1" ]] && ok "net.ipv4.conf.${EXTERNAL_IFACE}.rp_filter: $rp_ext" || fail "rp_filter ${EXTERNAL_IFACE}: got '${rp_ext:-EMPTY}'"

  ip_fwd=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")
  [[ "$ip_fwd" == "1" ]] && ok "net.ipv4.ip_forward: $ip_fwd" || fail "ip_forward: got '${ip_fwd:-EMPTY}'"

  # 5. Egress Ping Check
  if timeout 3 ping -c1 -W2 8.8.8.8 >/dev/null 2>&1; then
    ok "Internet reachable via ${EXTERNAL_IFACE}"
  else
    fail "Internet NOT reachable"
  fi

  # 6. Inter-peer Ping Check
  for peer in "${PEERS[@]}"; do
    local pname="${peer%%:*}"
    local pip="${peer##*:}"
    if timeout 3 ping -c1 -W2 "$pip" >/dev/null 2>&1; then
      ok "Peer ${pname} (${pip}) reachable"
    else
      fail "Peer ${pname} (${pip}) UNREACHABLE"
    fi
  done
}
