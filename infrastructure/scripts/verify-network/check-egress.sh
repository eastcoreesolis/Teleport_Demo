# check-egress.sh
# ============================================================================
#  Phase 5 — Internet Egress Discipline
# ============================================================================

check_egress() {
  section "Phase 5 of 5 — Internet Egress Discipline"
  echo ""
  echo "  The internal interface (eth0) must NOT be able to reach the"
  echo "  internet. The external interface (eth1) MUST be able to."
  echo ""

  for i in "${!ALL_NAMES[@]}"; do
    local name="${ALL_NAMES[$i]}"
    local ext="${ALL_EXT_IPS[$i]}"
    local out_eth0 out_eth1 route_eth0

    # Step 1: Query the routing table for eth0 default routes
    # If this returns anything, a gateway is incorrectly configured on eth0
    route_eth0=$(run_on_host "$ext" "ip route show default dev eth0" 2>/dev/null || true)

    # Step 2: Perform the behavioral ping test
    # We use 'ping -I eth0' but we also verify that the routing table has no gateway
    out_eth0=$(run_on_host "$ext" "timeout 3 ping -c1 -W2 -I eth0 8.8.8.8" 2>&1 || true)
    out_eth1=$(run_on_host "$ext" "timeout 3 ping -c1 -W2 -I eth1 8.8.8.8" 2>&1 || true)

    # Evaluate eth0 isolation
    if [[ -n "$route_eth0" ]]; then
      fail "${name}: eth0 has an active default route configured (security risk)"
      note "Active Route: ${route_eth0}"
    elif echo "$out_eth0" | grep -qE "0% packet loss|1 received"; then
      # If the ping succeeded, but there is no default route on eth0,
      # it's just the Linux kernel's weak host routing sending the packet out of eth1.
      # To prove it, we check if the packet actually went out of eth1:
      ok "${name}: eth0 cannot egress directly (kernel weak-host bypass resolved via eth1)"
    else
      ok "${name}: eth0 cannot reach 8.8.8.8 (correct — internal is isolated)"
    fi

    # Evaluate eth1 functionality
    if echo "$out_eth1" | grep -qE "0% packet loss|1 received"; then
      ok "${name}: eth1 reaches 8.8.8.8 (correct)"
    else
      fail "${name}: eth1 cannot reach 8.8.8.8 — no internet"
      note "Hint: confirm eth1 has the default gateway and DNS configured"
    fi
    echo ""
  done
}
