# collect-input.sh
# ============================================================================
#  Interactive input collection for cluster topology.
#
#  Defines globals:
#    SSH_USER, SSH_KEY
#    CTRL_NAME, CTRL_INT_IP, CTRL_EXT_IP
#    WORKER_NAMES[], WORKER_INT_IPS[], WORKER_EXT_IPS[]
#    ALL_NAMES[], ALL_EXT_IPS[], ALL_INT_IPS[]
#    INTERNAL_SUBNET
#
#  If all required variables are already set in the environment (e.g., when
#  invoked with --check), the prompts are skipped automatically.
# ============================================================================

collect_input() {
  # Skip if already populated (used by --check mode)
  if [[ -n "${SSH_USER:-}" && -n "${SSH_KEY:-}" && -n "${CTRL_NAME:-}" && -n "${CTRL_INT_IP:-}" ]]; then
    note "Using pre-loaded configuration (--check mode)"
    build_ssh_opts
    _build_node_arrays
    return 0
  fi

  # ---------- Step 1: SSH credentials ----------
  section "Step 1 of 3 — SSH Credentials"
  echo ""
  echo "  First, tell us how you normally log in to your K8s nodes."
  echo "  This is the same account you would use to run 'ssh <hostname>'."
  echo ""

  while true; do
    read -rp "  SSH username: " SSH_USER
    if [[ -n "$SSH_USER" ]]; then
      ok "SSH username set to: ${BLD}${SSH_USER}${NC}"
      break
    else
      fail "SSH username cannot be empty. Please try again."
      echo ""
    fi
  done

  echo ""
  echo "  Next, tell us where your SSH private key is stored."
  echo ""
  echo "    • To proceed with the default path (~/.ssh/id_rsa), just press ENTER."
  echo "    • Otherwise, enter the path to the SSH private key:"
  echo ""

  while true; do
    read -rp "  SSH private key path [~/.ssh/id_rsa]: " SSH_KEY
    SSH_KEY=${SSH_KEY:-~/.ssh/id_rsa}
    SSH_KEY="${SSH_KEY/#\~/$HOME}"

    if [[ -f "$SSH_KEY" ]]; then
      ok "SSH private key set to: ${BLD}${SSH_KEY}${NC}"
      break
    else
      warn "The file '${SSH_KEY}' does not exist on this machine."
      echo "      You can proceed anyway if you plan to configure keys later."
      read -rp "      Accept this path anyway? [y/N]: " accept_anyway
      if [[ "$accept_anyway" =~ ^[yY](es)?$ ]]; then
        ok "SSH private key path accepted (file missing): ${BLD}${SSH_KEY}${NC}"
        break
      fi
      echo ""
    fi
  done

  build_ssh_opts

  # ---------- Step 2: Control plane ----------
  section "Step 2 of 3 — Control Plane Node"
  echo ""
  echo "  Enter the hostname and IP addresses of your control plane node."
  echo "  This is the machine that will run 'kubeadm init'."
  echo ""
  echo "  Internal IP — the address on the cluster-only network (eth0)"
  echo "  External IP — the address on your corporate network (eth1)"
  echo ""

  while true; do
    read -rp "  Control plane hostname (e.g., kcontrol) [kcontrol]: " CTRL_NAME
    CTRL_NAME=${CTRL_NAME:-kcontrol}
    [[ -n "$CTRL_NAME" ]] && break
    fail "Hostname cannot be empty. Please try again."
  done

  while true; do
    read -rp "  Control plane INTERNAL IP (e.g., 192.168.2.85) [192.168.2.85]: " CTRL_INT_IP
    CTRL_INT_IP=${CTRL_INT_IP:-192.168.2.85}
    if [[ -z "$CTRL_INT_IP" ]]; then
      fail "Internal IP cannot be empty."
    elif is_valid_ip "$CTRL_INT_IP"; then
      break
    else
      fail "'${CTRL_INT_IP}' is not a valid IPv4 address."
    fi
  done

  while true; do
    read -rp "  Control plane EXTERNAL IP (e.g., 192.168.1.85) [192.168.1.85]: " CTRL_EXT_IP
    CTRL_EXT_IP=${CTRL_EXT_IP:-192.168.1.85}
    if [[ -z "$CTRL_EXT_IP" ]]; then
      fail "External IP cannot be empty."
    elif is_valid_ip "$CTRL_EXT_IP"; then
      break
    else
      fail "'${CTRL_EXT_IP}' is not a valid IPv4 address."
    fi
  done

  ok "Control plane: ${BLD}${CTRL_NAME}${NC} — internal ${BLD}${CTRL_INT_IP}${NC}, external ${BLD}${CTRL_EXT_IP}${NC}"

  # ---------- Step 3: Worker nodes ----------
  section "Step 3 of 3 — Worker Nodes"
  echo ""
  echo "  Now enter the same information for each worker node."
  echo "  You will be prompted one worker at a time."
  echo ""

  while true; do
    read -rp "  How many worker nodes does this cluster have? [2]: " WORKER_COUNT
    WORKER_COUNT=${WORKER_COUNT:-2}
    if [[ "$WORKER_COUNT" =~ ^[0-9]+$ ]] && (( WORKER_COUNT > 0 )); then
      break
    else
      fail "Please enter a positive whole number (e.g., 2)."
    fi
  done

  echo ""
  echo "  ${BLD}Tip:${NC} Workers are usually named kworkera, kworkerb, etc."
  echo "       IPs typically follow the control plane's scheme, with the last"
  echo "       octet incremented (e.g., 192.168.2.86, 192.168.2.87)."
  echo ""

  WORKER_NAMES=()
  WORKER_INT_IPS=()
  WORKER_EXT_IPS=()
  WORKER_LETTERS=(a b c d e f g h i j k l m n o p q r s t u v w x y z)

  for ((i=0; i<WORKER_COUNT; i++)); do
    default_name="kworker${WORKER_LETTERS[$i]:-$i}"
    default_int_suffix=$((86 + i))

    ctrl_int_octets=(${CTRL_INT_IP//./ })
    default_int="${ctrl_int_octets[0]:-192}.${ctrl_int_octets[1]:-168}.${ctrl_int_octets[2]:-2}.${default_int_suffix}"

    ctrl_ext_octets=(${CTRL_EXT_IP//./ })
    default_ext="${ctrl_ext_octets[0]:-192}.${ctrl_ext_octets[1]:-168}.${ctrl_ext_octets[2]:-1}.${default_int_suffix}"

    echo -e "  ${BLD}--- Worker $((i+1)) of $WORKER_COUNT ---${NC}"

    while true; do
      read -rp "  Hostname [${default_name}]: " WNAME
      WNAME=${WNAME:-$default_name}
      [[ -n "$WNAME" ]] && break
      fail "Hostname cannot be empty."
    done

    while true; do
      read -rp "  Internal IP [${default_int}]: " WINT
      WINT=${WINT:-$default_int}
      is_valid_ip "$WINT" && break
      fail "'${WINT}' is not a valid IPv4 address."
    done

    while true; do
      read -rp "  External IP [${default_ext}]: " WEXT
      WEXT=${WEXT:-$default_ext}
      is_valid_ip "$WEXT" && break
      fail "'${WEXT}' is not a valid IPv4 address."
    done

    WORKER_NAMES+=("$WNAME")
    WORKER_INT_IPS+=("$WINT")
    WORKER_EXT_IPS+=("$WEXT")
    ok "Worker $((i+1)): ${BLD}${WNAME}${NC} — internal ${BLD}${WINT}${NC}, external ${BLD}${WEXT}${NC}"
    echo ""
  done

  # ---------- Review ----------
  section "Review Your Configuration"
  echo ""
  echo "  Before we run the checks, please confirm the details below."
  echo ""
  echo -e "  ${BLD}SSH access:${NC}      ${SSH_USER}@<host> using ${SSH_KEY}"
  echo -e "  ${BLD}Control plane:${NC}   ${CTRL_NAME} (int: ${CTRL_INT_IP}, ext: ${CTRL_EXT_IP})"
  for i in "${!WORKER_NAMES[@]}"; do
    echo -e "  ${BLD}Worker $((i+1)):${NC}        ${WORKER_NAMES[$i]} (int: ${WORKER_INT_IPS[$i]}, ext: ${WORKER_EXT_IPS[$i]})"
  done
  echo ""

  # Attempt to install SSH keys to all nodes automatically
  echo -e "  ${BLD}Attempting to install your SSH public key on all nodes...${NC}"
  echo "  (You may be prompted for each node's password.)"
  echo ""
  ALL_IPS_FOR_KEYS=("$CTRL_EXT_IP" "${WORKER_EXT_IPS[@]}" "$CTRL_INT_IP" "${WORKER_INT_IPS[@]}")
  for ip in "${ALL_IPS_FOR_KEYS[@]}"; do
    echo -e "  ${CYN}→${NC} ssh-copy-id -i ${SSH_KEY} ${SSH_USER}@${ip}"
    ssh-copy-id -i "$SSH_KEY" "${SSH_USER}@${ip}" 2>/dev/null \
      && ok "Key installed to ${ip}" \
      || warn "Could not install key to ${ip} (may already exist or be unreachable)"
  done
  echo ""

  read -rp "  Press ENTER to run the verification, or Ctrl+C to cancel: " _
  echo ""

  _build_node_arrays
}

# ---------- Internal helper: build the aggregated node arrays ----------
_build_node_arrays() {
  INTERNAL_SUBNET=$(echo "$CTRL_INT_IP" | cut -d. -f1-3)
  ALL_NAMES=("$CTRL_NAME" "${WORKER_NAMES[@]}")
  ALL_EXT_IPS=("$CTRL_EXT_IP" "${WORKER_EXT_IPS[@]}")
  ALL_INT_IPS=("$CTRL_INT_IP" "${WORKER_INT_IPS[@]}")
}

