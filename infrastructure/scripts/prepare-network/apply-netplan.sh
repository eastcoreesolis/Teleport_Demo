# prepare-network/apply-netplan.sh
# ============================================================================
#  Builds the netplan YAML and applies it.
# ============================================================================

apply_netplan() {
  section "Step 3 of 4 — Netplan Configuration"

  # 1. Prepare DNS/Search variables
  export DNS_LINES=""
  IFS=',' read -ra DNS_ARRAY <<< "$THIS_DNS"
  for d in "${DNS_ARRAY[@]}"; do
    DNS_LINES="${DNS_LINES}          - ${d}"$'\n'
  done

  export SEARCH_BLOCK=""
  if [[ -n "$THIS_SEARCH" ]]; then
    export SEARCH_BLOCK="        search:
          - ${THIS_SEARCH}"
  fi

  # 2. Use envsubst to safely inject variables into the template
  envsubst < "${SCRIPT_DIR}/netplan.template" > /tmp/99-k8s.yaml

  echo -e "${CYN}──── /etc/netplan/99-k8s.yaml ────────────────────────────────${NC}"
  cat /tmp/99-k8s.yaml | sed 's/^/    /'
  echo -e "${CYN}──────────────────────────────────────────────────────────────${NC}"

  # 3. Apply
  read -rp "  Apply this netplan? [Y/n]: " confirm
  [[ "${confirm:-Y}" =~ ^[nN] ]] && return 1

  mv /tmp/99-k8s.yaml /etc/netplan/99-k8s.yaml
  chmod 600 /etc/netplan/99-k8s.yaml
  netplan apply
}
