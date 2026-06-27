# kubeadm-install/02-containerd.sh
# Phase 2: Install and configure the containerd CRI runtime

source "${SCRIPT_DIR}/lib/version-pinning.sh"

install_containerd() {
  section "Phase 2 of 4 — Container Runtime (containerd)"
  echo ""
  
  # Install Docker's official repository so we get the latest containerd builds
  echo -e "  ${CYN}→${NC} Adding Docker APT repository (for containerd)..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
  chmod a+r /etc/apt/keyrings/docker.gpg
  
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt-get update -y >/dev/null

  echo -e "  ${CYN}→${NC} Installing containerd.io ${CONTAINERD_VERSION}..."
  apt-get install -y containerd.io=${CONTAINERD_VERSION} >/dev/null
  ok "containerd.io installed"
  
  # Configure containerd to use systemd cgroup driver
  echo -e "  ${CYN}→${NC} Configuring containerd for systemd cgroups..."
  mkdir -p /etc/containerd
  containerd config default | tee /etc/containerd/config.toml >/dev/null
  
  # Use sed to reliably set the cgroup driver
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
  
  systemctl restart containerd
  sleep 3
  
  if systemctl is-active --quiet containerd; then
    ok "containerd service is active and running"
  else
    fail "containerd service failed to start. Check 'journalctl -xeu containerd'"
    return 1
  fi
}
