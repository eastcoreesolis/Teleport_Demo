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
    local out_eth0 out_eth1
    out_eth0=$(run_on_host "$ext" "timeout 3 ping -c1 -W2 -I eth0 8.8.8.8" 2>&1 || true)
    out_eth1=$(run_on_host "$ext" "timeout 3 ping -c1 -W2 -I eth1 8.8.8.8" 2>&1 || true)

    if echo "$out_eth0" | grep -qE "0% packet loss|1 received"; then
      fail "${name}: eth0 reaches the internet (unexpected — eth0 is internal-only)"
      note "Hint: confirm eth0 has no gateway in its netplan config"
    else
      ok "${name}: eth0 cannot reach 8.8.8.8 (correct)"
    fi

    if echo "$out_eth1" | grep -qE "0% packet loss|1 received"; then
      ok "${name}: eth1 reaches 8.8.8.8 (correct)"
    else
      fail "${name}: eth1 cannot reach 8.8.8.8 — no internet"
      note "Hint: confirm eth1 has the default gateway and DNS configured"
    fi
  done
}
