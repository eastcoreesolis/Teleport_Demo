# prepare-network/lib/topology.sh
# ============================================================================
#  Auto-detects the node's role and network defaults based on hostname.
#
#  Sets the following globals:
#    DEFAULT_THIS_HOSTNAME, DEFAULT_INT_IP, DEFAULT_EXT_IP
#    DEFAULT_PEER_NAMES[], DEFAULT_PEER_IPS[]
#    INTERNAL_IFACE, EXTERNAL_IFACE
# ============================================================================

DEFAULT_GATEWAY="192.168.1.254"
DEFAULT_DNS="192.168.1.70,192.168.1.254"
DEFAULT_SEARCH="eastcore.local"

# ---------- Auto-detect role from hostname ----------
auto_detect_role() {
  local hn
  hn=$(hostname)

  if [[ "$hn" =~ (control|master|kcontrol) ]]; then
    DEFAULT_THIS_HOSTNAME="kcontrolplane"
    DEFAULT_INT_IP="192.168.2.85"
    DEFAULT_EXT_IP="192.168.1.85"
    DEFAULT_PEER_NAMES=("kworkera" "kworkerb")
    DEFAULT_PEER_IPS=("192.168.2.86" "192.168.2.87")
  elif [[ "$hn" =~ (workera|worker1|worker-a|kworker1) ]]; then
    DEFAULT_THIS_HOSTNAME="kworkera"
    DEFAULT_INT_IP="192.168.2.86"
    DEFAULT_EXT_IP="192.168.1.86"
    DEFAULT_PEER_NAMES=("kcontrolplane" "kworkerb")
    DEFAULT_PEER_IPS=("192.168.2.85" "192.168.2.87")
  elif [[ "$hn" =~ (workerb|worker2|worker-b|kworker2) ]]; then
    DEFAULT_THIS_HOSTNAME="kworkerb"
    DEFAULT_INT_IP="192.168.2.87"
    DEFAULT_EXT_IP="192.168.1.87"
    DEFAULT_PEER_NAMES=("kcontrolplane" "kworkera")
    DEFAULT_PEER_IPS=("192.168.2.85" "192.168.2.86")
  else
    DEFAULT_THIS_HOSTNAME="$hn"
    DEFAULT_INT_IP="192.168.2.85"
    DEFAULT_EXT_IP="192.168.1.85"
    DEFAULT_PEER_NAMES=("kworkera" "kworkerb")
    DEFAULT_PEER_IPS=("192.168.2.86" "192.168.2.87")
  fi
}

# ---------- Auto-detect interface names ----------
detect_iface() {
  INTERNAL_IFACE=$(ls /sys/class/net/ | grep -v "lo" | head -1)
  EXTERNAL_IFACE=$(ls /sys/class/net/ | grep -v "lo" | sed -n '2p')
  ok "Detected internal interface: ${BLD}${INTERNAL_IFACE}${NC}"
  ok "Detected external interface: ${BLD}${EXTERNAL_IFACE}${NC}"
}
