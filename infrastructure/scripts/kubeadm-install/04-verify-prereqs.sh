# kubeadm-install/04-verify-prereqs.sh
# Phase 4: Verify the environment is ready for 'kubeadm init/join'

verify_prereqs() {
  section "Phase 4 of 4 — Prerequisites Verification"
  echo ""
  echo "  Verifying that all services and configurations are active..."
  echo ""

  # 1. Check that swap is actually off
  if [[ "$(swapon --show)" == "" ]]; then
    ok "swap is completely disabled"
  else
    fail "swap is STILL ACTIVE: $(swapon --show)"
    return 1
  fi

  # 2. Check that required kernel modules are loaded
  if lsmod | grep -q br_netfilter && lsmod | grep -q overlay; then
    ok "br_netfilter and overlay modules are loaded"
  else
    fail "Required kernel modules are missing. Check 'lsmod | grep -E \"br_netfilter|overlay\"'"
    return 1
  fi

  # 3. Wait for containerd socket to be available
  echo -e "  ${CYN}→${NC} Waiting for containerd to expose its socket..."
  local waited=0
  while (( waited < 30 )); do
    if [[ -S /run/containerd/containerd.sock ]]; then
      ok "containerd socket is live at /run/containerd/containerd.sock"
      break
    fi
    sleep 1
    ((waited++))
  done
  if [[ $waited -ge 30 ]]; then
    fail "containerd socket did not appear after 30 seconds"
    return 1
  fi

  # 4. Verify the kubeadm binary actually works
  if kubeadm version >/dev/null 2>&1; then
    local kb_ver
    kb_ver=$(kubeadm version -o short)
    ok "kubeadm is responsive: ${kb_ver}"
  else
    fail "kubeadm binary failed to execute. Check installation logs."
    return 1
  fi
  echo ""
}
