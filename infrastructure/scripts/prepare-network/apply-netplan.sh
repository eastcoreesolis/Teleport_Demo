# prepare-network/apply-netplan.sh
# ============================================================================
#  Builds the netplan YAML and applies it.
# ============================================================================

# Build netplan YAML content into stdout
build_netplan_content() {
  local int_ip="$1"; local ext_ip="$2"; local gateway="$3"
  local dns="$4"; local search="$5"
  local int_iface="$6"; local ext_iface="$7"

  # Build DNS lines with correct indentation
  local dns_lines=""
  IFS=',' read -ra dns_array <<< "$dns"
  for d in "${dns_array[@]}"; do
    dns_lines="${dns_lines}          - ${d}
"
  done

  # Build search block
  local search_block=""
  if [[ -n "$search" ]]; then
    search_block="          search:
            - ${search}
"
  fi

  cat <<NETPLAN_EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${int_iface}:
      dhcp4: no
      dhcp6: no
      optional: true
      addresses:
        - ${int_ip}/24
    ${ext_iface}:
      dhcp4: no
      dhcp6: no
      optional: true
      addresses:
        - ${ext_ip}/24
      routes:
        - to: default
          via: ${gateway}
          metric: 100
      nameservers:
        addresses:
${dns_lines}${search_block}NETPLAN_EOF
}

apply_netplan() {
  section "Step 3 of 4 — Netplan Configuration"
  echo ""
  echo "  The following netplan will be written to /etc/netplan/99-k8s.yaml:"
  echo ""
  echo -e "${CYN}──── /etc/netplan/99-k8s.yaml ────────────────────────────────${NC}"
  build_netplan_content \
    "$THIS_INT_IP" "$THIS_EXT_IP" "$THIS_GATEWAY" \
    "$THIS_DNS" "$THIS_SEARCH" \
    "$INTERNAL_IFACE" "$EXTERNAL_IFACE" | sed 's/^/    /'
  echo -e "${CYN}──────────────────────────────────────────────────────────────${NC}"
  echo ""

  local confirm_netplan=""
  read -rp "  Apply this netplan? [Y/n]: " confirm_netplan
  confirm_netplan=${confirm_netplan:-Y}
  if [[ "$confirm_netplan" =~ ^[nN](o)?$ ]]; then
    warn "Skipping netplan application."
    return 1
  fi

  echo ""
  echo -e "  ${CYN}→${NC} Writing /etc/netplan/99-k8s.yaml..."
  build_netplan_content \
    "$THIS_INT_IP" "$THIS_EXT_IP" "$THIS_GATEWAY" \
    "$THIS_DNS" "$THIS_SEARCH" \
    "$INTERNAL_IFACE" "$EXTERNAL_IFACE" > /etc/netplan/99-k8s.yaml
  chmod 600 /etc/netplan/99-k8s.yaml

  # Remove conflicting default configs
  for f in /etc/netplan/50-cloud-init.yaml /etc/netplan/01-netcfg.yaml; do
    if [[ -f "$f" ]]; then
      echo -e "  ${CYN}→${NC} Removing conflicting ${f}..."
      mv "$f" "${f}.disabled"
    fi
  done

  echo -e "  ${CYN}→${NC} Applying netplan..."
  if netplan apply; then
    ok "Netplan applied successfully"
    sleep 2
    return 0
  else
    fail "Netplan apply failed. Check: netplan --debug apply"
    echo ""
    echo "  Current netplan files:"
    ls -la /etc/netplan/
    echo ""
    echo "  Contents of 99-k8s.yaml:"
    cat /etc/netplan/99-k8s.yaml
    return 1
  fi
}
