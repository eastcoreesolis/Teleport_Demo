# kubeadm-install/04-verify-prereqs.sh
# ============================================================================
#  Phase 4: Post-installation environment validation
# ============================================================================

verify_prereqs() {
  section "Phase 4 of 4 — Installation Verification"
  echo ""
  echo "  Verifying system configurations and daemon socket integrity..."
  echo ""

  # 1. Swap status check
  if [[ -z "$(swapon --show)" ]]; then
    ok "swap is completely disabled"
  else
    fail "swap remains active"
    return 1
  fi

  # 2. Kernel modules verification
  if lsmod | grep -q br_netfilter && lsmod | grep -q overlay; then
    ok "br_netfilter and overlay modules are actively loaded in the kernel"
  else
    fail "Required kernel routing modules are missing"
    return 1
  fi

  # 3. Wait up to 15 seconds for containerd interface to stabilize
  echo -e "  ${CYN}→${NC} Verifying containerd daemon socket..."
  local waited=0
  while (( waited < 15 )); do
    if [[ -S /run/containerd/containerd.sock ]]; then
      ok "containerd socket is live at /run/containerd/containerd.sock"
      break
    fi
    sleep 1
    ((waited++))
  done

  if (( waited >= 15 )); then
    fail "containerd unix socket did not initialize"
    return 1
  fi

  # 4. Kubeadm verification
  if kubeadm version >/dev/null 2>&1; then
    local kb_ver
    kb_ver=$(kubeadm version -o short)
    ok "kubeadm executable is responsive (version: ${kb_ver})"
  else
    fail "kubeadm package failed execution verification"
    return 1
  fi
  echo ""
}
