# check-node-config.sh
# ============================================================================
#  Phase 2 — Per-Node Network Configuration Dump
# ============================================================================

check_node_config() {
  section "Phase 2 of 5 — Per-Node Network Configuration"
  echo ""
  echo "  Pulling the network configuration from each node and displaying"
  echo "  it in a consolidated report."
  echo ""

  _dump_node "$CTRL_NAME" "$CTRL_INT_IP" "$CTRL_EXT_IP"
  for i in "${!WORKER_NAMES[@]}"; do
    _dump_node "${WORKER_NAMES[$i]}" "${WORKER_INT_IPS[$i]}" "${WORKER_EXT_IPS[$i]}"
  done
}

_dump_node() {
  local label="$1"; local int_ip="$2"; local ext_ip="$3"
  echo ""
  echo -e "  ${BLD}╭─ ${label} ──────────────────────────────────────────${NC}"
  echo -e "  ${BLD}│${NC}  Internal IP:  ${int_ip}"
  echo -e "  ${BLD}│${NC}  External IP:  ${ext_ip}"
  echo -e "  ${BLD}╰───────────────────────────────────────────────────${NC}"
  echo ""

  echo -e "    ${BLD}Interfaces:${NC}"
  run_on_host "$ext_ip" "ip -br addr show eth0" | sed 's/^/      eth0 → /'
  run_on_host "$ext_ip" "ip -br addr show eth1" | sed 's/^/      eth1 → /'
  echo ""

  echo -e "    ${BLD}Routing table:${NC}"
  run_on_host "$ext_ip" "ip route show" | sed 's/^/      /'
  echo ""

  echo -e "    ${BLD}DNS configuration (/etc/resolv.conf):${NC}"
  run_on_host "$ext_ip" "cat /etc/resolv.conf 2>/dev/null" | sed 's/^/      /'
  echo ""

  echo -e "    ${BLD}Reverse-path filter settings:${NC}"
  run_on_host "$ext_ip" "sysctl -n net.ipv4.conf.all.rp_filter net.ipv4.conf.eth0.rp_filter net.ipv4.conf.eth1.rp_filter 2>/dev/null" \
    | awk 'NR==1{print "      all.rp_filter   =", $1} NR==2{print "      eth0.rp_filter  =", $1} NR==3{print "      eth1.rp_filter  =", $1}'
  echo ""

  echo -e "    ${BLD}Hostname (fully qualified):${NC}"
  run_on_host "$ext_ip" "hostname -f 2>/dev/null" | sed 's/^/      /'
  echo ""
}
