# check-connectivity.sh
# ============================================================================
#  Phase 3 — Cross-Node ICMP Connectivity (internal network)
# ============================================================================

check_connectivity() {
  section "Phase 3 of 5 — Cross-Node Connectivity"
  echo ""
  echo "  Pinging each node from every other node, using the INTERNAL IPs"
  echo "  (this is the path kubelet, kube-proxy, and the CNI will use)."
  echo ""

  for i in "${!ALL_NAMES[@]}"; do
    local src_name="${ALL_NAMES[$i]}"
    local src_ext="${ALL_EXT_IPS[$i]}"
    echo -e "  ${BLD}From ${src_name}:${NC}"
    for j in "${!ALL_NAMES[@]}"; do
      [[ "$i" == "$j" ]] && continue
      local target_int="${ALL_INT_IPS[$j]}"
      local target_name="${ALL_NAMES[$j]}"
      local out
      out=$(run_on_host "$src_ext" "ping -c2 -W2 $target_int" 2>&1 || true)
      if echo "$out" | grep -q "0% packet loss"; then
        ok "${target_name} (${target_int}) reachable"
      else
        fail "${target_name} (${target_int}) UNREACHABLE"
        note "Hint: check the internal switch / VM network adapter attached to eth0"
        echo "$out" | grep -E "From|unreachable|Network" | sed 's/^/        /'
      fi
    done
    echo ""
  done
}

