# prepare-network/verify-local.sh
# ============================================================================
#  Post-apply verification: confirms the configuration took effect.
# ============================================================================

# Query interface IP using native iproute2 filter matching
get_interface_ip() {
  local iface="$1"
  local target_ip="$2"

  # Check if the exact expected IP is assigned to this interface
  if ip -4 addr show dev "$iface" 2>/dev/null | grep -qF "inet ${target_ip}/"; then
    echo "$target_ip"
  else
    # Fallback: grab whatever IPv4 is there, or return EMPTY
    local current_ip
    current_ip=$(ip -4 addr show dev "$iface" 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -n1)
    echo "${current_ip:-EMPTY}"
  fi
}

wait_for_network() {
  echo ""
  echo -e "  ${CYN}→${NC} Waiting 5 seconds for Netplan changes to apply and links to settle..."
  sleep 5

  echo -e "  ${CYN}→${NC} Verifying link carrier states..."
  local waited=0
  while (( waited < 10 )); do
    local int_up=0
    local ext_up=0

    # Check if interfaces physically exist and are UP
    ip link show dev "$INTERNAL_IFACE" 2>/dev/null | grep -q "state UP" && int_up=1
    ip link show dev "$EXTERNAL_IFACE" 2>/dev/null | grep -q "state UP" && ext_up=1

    if [[ "$int_up" -eq 1 && "$ext_up" -eq 1 ]]; then
      ok "Physical links are UP and active"
      return 0
    fi
    sleep 1
    ((waited++))
  done
  warn "One or more physical links are not reporting UP. Proceeding anyway..."
}

verify_local_config() {
  section "Post-Apply Verification"
  wait_for_network
  echo ""
  echo "  Verifying the new configuration took effect..."
  echo ""

  # 1. Verify Internal Interface IP
  local int_actual
  int_actual=$(get_interface_ip "$INTERNAL_IFACE" "$THIS_INT_IP")
  if [[ "$int_actual" == "$THIS_INT_IP" ]]; then
    ok "${INTERNAL_IFACE} IP: $int_actual"
  else
    fail "${INTERNAL_IFACE} IP: expected '${THIS_INT_IP}', got '${int_actual}'"
  fi

  # 2. Verify External Interface IP
  local ext_actual
  ext_actual=$(get_interface_ip "$EXTERNAL_IFACE" "$THIS_EXT_IP")
  if [[ "$ext_actual" == "$THIS_EXT_IP" ]]; then
    ok "${EXTERNAL_IFACE} IP: $ext_actual"
  else
    fail "${EXTERNAL_IFACE} IP: expected '${THIS_EXT_IP}', got '${ext_actual}'"
  fi

  # 3. Verify Default Route
  local route_actual
  route_actual=$(ip route show default 2>/dev/null | head -n1)
  if echo "$route_actual" | grep -qF "via ${THIS_GATEWAY} dev ${EXTERNAL_IFACE}"; then
    ok "default route: $route_actual"
  else
    fail "default route: expected 'via ${THIS_GATEWAY} dev ${EXTERNAL_IFACE}', got '${route_actual:-EMPTY}'"
  fi

  # 4. Verify Sysctl settings
  local rp_all rp_int rp_ext ip_fwd

  rp_all=$(sysctl -n net.ipv4.conf.all.rp_filter 2>/dev/null)
  [[ "$rp_all" == "2" ]] && ok "net.ipv4.conf.all.rp_filter: $rp_all" || fail "rp_filter all: expected '2', got '${rp_all:-EMPTY}'"

  rp_int=$(sysctl -n "net.ipv4.conf.${INTERNAL_IFACE}.rp_filter" 2>/dev/null)
  [[ "$rp_int" == "2" ]] && ok "net.ipv4.conf.${INTERNAL_IFACE}.rp_filter: $rp_int" || fail "rp_filter ${INTERNAL_IFACE}: expected '2', got '${rp_int:-EMPTY}'"

  rp_ext=$(sysctl -n "net.ipv4.conf.${EXTERNAL_IFACE}.rp_filter" 2>/dev/null)
  [[ "$rp_ext" == "2" ]] && ok "net.ipv4.conf.${EXTERNAL_IFACE}.rp_filter: $rp_ext" || fail "rp_filter ${EXTERNAL_IFACE}: expected '2', got '${rp_ext:-EMPTY}'"

  ip_fwd=$(sysctl -n net.ipv4.ip_forward 2>/dev/null)
  [[ "$ip_fwd" == "1" ]] && ok "net.ipv4.ip_forward: $ip_fwd" || fail "ip_forward: expected '1', got '${ip_fwd:-EMPTY}'"

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
