# prepare-network/collect-config.sh
# ============================================================================
#  Interactive prompts for node identity, IP config, and peer nodes.
#
#  Sets globals:
#    THIS_HOSTNAME, THIS_INT_IP, THIS_EXT_IP
#    THIS_GATEWAY, THIS_DNS, THIS_SEARCH
#    PEERS[]
# ============================================================================

collect_node_config() {
  section "Step 1 of 4 — Node Identity and IP Configuration"
  echo ""

  # Hostname
  read -rp "  This node's hostname [${DEFAULT_THIS_HOSTNAME}]: " THIS_HOSTNAME
  THIS_HOSTNAME=${THIS_HOSTNAME:-$DEFAULT_THIS_HOSTNAME}
  ok "Hostname: ${BLD}${THIS_HOSTNAME}${NC}"

  # Internal IP
  while true; do
    read -rp "  INTERNAL IP (${INTERNAL_IFACE}) [${DEFAULT_INT_IP}]: " THIS_INT_IP
    THIS_INT_IP=${THIS_INT_IP:-$DEFAULT_INT_IP}
    is_valid_ip "$THIS_INT_IP" && break
    fail "'${THIS_INT_IP}' is not a valid IPv4 address."
  done
  ok "Internal IP: ${BLD}${THIS_INT_IP}${NC}"

  # External IP
  while true; do
    read -rp "  EXTERNAL IP (${EXTERNAL_IFACE}) [${DEFAULT_EXT_IP}]: " THIS_EXT_IP
    THIS_EXT_IP=${THIS_EXT_IP:-$DEFAULT_EXT_IP}
    is_valid_ip "$THIS_EXT_IP" && break
    fail "'${THIS_EXT_IP}' is not a valid IPv4 address."
  done
  ok "External IP: ${BLD}${THIS_EXT_IP}${NC}"

  # Gateway
  while true; do
    read -rp "  External default gateway [${DEFAULT_GATEWAY}]: " THIS_GATEWAY
    THIS_GATEWAY=${THIS_GATEWAY:-$DEFAULT_GATEWAY}
    is_valid_ip "$THIS_GATEWAY" && break
    fail "'${THIS_GATEWAY}' is not a valid IPv4 address."
  done
  ok "Default gateway: ${BLD}${THIS_GATEWAY}${NC}"

  # DNS
  read -rp "  DNS servers [${DEFAULT_DNS}]: " THIS_DNS
  THIS_DNS=${THIS_DNS:-$DEFAULT_DNS}
  ok "DNS servers: ${BLD}${THIS_DNS}${NC}"

  # Search domain
  read -rp "  DNS search domain [${DEFAULT_SEARCH}]: " THIS_SEARCH
  THIS_SEARCH=${THIS_SEARCH:-$DEFAULT_SEARCH}
  ok "Search domain: ${BLD}${THIS_SEARCH:-none}${NC}"
}

collect_peer_nodes() {
  section "Step 2 of 4 — Peer Cluster Nodes"
  echo ""
  echo "  Confirm the hostname and internal IPs of the other cluster nodes."
  echo "  These will be added to /etc/hosts for static resolution."
  echo ""

  PEERS=()
  local peer_count
  read -rp "  How many peer nodes? [2]: " peer_count
  peer_count=${peer_count:-2}

  for ((i=0; i<peer_count; i++)); do
    local default_pname="${DEFAULT_PEER_NAMES[$i]:-kworker}"
    local default_pip="${DEFAULT_PEER_IPS[$i]:-192.168.2.$((86 + i))}"
    local pname pip

    echo -e "  ${BLD}--- Peer $((i+1)) of $peer_count ---${NC}"

    read -rp "    Hostname [${default_pname}]: " pname
    pname=${pname:-$default_pname}

    while true; do
      read -rp "    Internal IP [${default_pip}]: " pip
      pip=${pip:-$default_pip}
      is_valid_ip "$pip" && break
      fail "Invalid IPv4 address."
    done

    PEERS+=("${pname}:${pip}")
    ok "Peer $((i+1)): ${BLD}${pname}${NC} (${pip})"
    echo ""
  done
}
