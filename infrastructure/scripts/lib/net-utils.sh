# lib/net-utils.sh
# ============================================================================
#  Network utilities shared between prepare-network.sh and verify-network.sh
# ============================================================================

# ---------- IP address validation ----------
is_valid_ip() {
  local ip="$1"
  if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    local OIFS="$IFS"
    IFS='.'
    local ip_array=($ip)
    IFS="$OIFS"
    if (( ip_array[0] <= 255 && ip_array[1] <= 255 && ip_array[2] <= 255 && ip_array[3] <= 255 )); then
      return 0
    fi
  fi
  return 1
}

# ---------- Detect primary interface name ----------
# Modern systemd systems use predictable names. Falls back to eth0/eth1.
detect_interface() {
  local role="$1"   # "internal" or "external"
  local idx=0
  [[ "$role" == "external" ]] && idx=1
  ip -br link show | awk -v idx="$idx" 'NR==idx+1 {print $1}' | head -n 1
}

# ---------- Detect the active interface name (e.g., enp0s3 vs eth0) ----------
get_active_ifs() {
  ip -br link show | awk '$2 == "UP" {print $1}' | grep -v "lo" | head -n 2
}
