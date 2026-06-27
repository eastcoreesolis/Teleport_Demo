# check-routes.sh
# ============================================================================
#  Phase 4 — Default Route Placement
# ============================================================================

check_routes() {
  section "Phase 4 of 5 — Default Route Placement"
  echo ""
  echo "  The cluster's internal network (eth0) should NOT have a default"
  echo "  route. Only the external interface (eth1) should reach the internet."
  echo ""

  for i in "${!ALL_NAMES[@]}"; do
    local name="${ALL_NAMES[$i]}"
    local ext="${ALL_EXT_IPS[$i]}"
    local routes
    routes=$(run_on_host "$ext" "ip route show default" 2>&1)
    if echo "$routes" | grep -q "dev eth1"; then
      ok "${name}: default route via eth1 (correct)"
    elif echo "$routes" | grep -q "dev eth0"; then
      fail "${name}: default route via eth0 — this will cause asymmetric routing"
      note "Hint: remove the gateway from the eth0 netplan configuration"
    else
      fail "${name}: no default route found — node will have no internet access"
      note "Hint: add a default gateway on eth1 in netplan"
    fi
  done
}

