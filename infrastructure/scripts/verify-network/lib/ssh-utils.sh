# lib/ssh-utils.sh
# ============================================================================
#  SSH and network utilities: is_valid_ip, run_on_host, build_ssh_opts
#
#  Expects the following globals to be set by collect-input.sh:
#    SSH_USER, SSH_KEY
#
#  Exposes:
#    SSH_OPTS  (array)  — built by build_ssh_opts
#    run_on_host        — execute a command on a remote host
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

# ---------- Build SSH options array ----------
# Called by collect-input.sh after SSH_USER and SSH_KEY are known
build_ssh_opts() {
  SSH_OPTS=(-i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes)
}

# ---------- Run a command on a remote host ----------
# Usage: run_on_host <ip> <command...>
run_on_host() {
  local host_ip="$1"; shift
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${host_ip}" "$@" 2>&1
}
