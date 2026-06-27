# kubeadm-install/03-kubetools.sh
# Phase 3: Install Kubernetes toolchain (kubeadm, kubelet, kubectl)

source "${SCRIPT_DIR}/lib/version-pinning.sh"

install_kubetools() {
  section "Phase 3 of 4 — Kubernetes Toolchain (kubeadm, kubelet, kubectl)"
  echo ""
  
  echo -e "  ${CYN}→${NC} Adding Kubernetes APT repository (${KUBERNETES_REPO_VERSION})..."
  curl -fsSL "https://pkgs.k8s.io/core:/stable:/${KUBERNETES_REPO_VERSION}/deb/Release.key" | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg --yes
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBERNETES_REPO_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
  apt-get update -y >/dev/null

  echo -e "  ${CYN}→${NC} Installing Kubernetes components (${K8S_VERSION})..."
  apt-get install -y kubelet=${K8S_VERSION} kubeadm=${K8S_VERSION} kubectl=${K8S_VERSION} >/dev/null
  
  # Hold the packages so they don't get upgraded during normal apt upgrades
  apt-mark hold kubelet kubeadm kubectl
  ok "kubeadm, kubelet, kubectl installed and held at ${K8S_VERSION}"
  
  # Reload systemd and enable kubelet
  echo -e "  ${CYN}→${NC} Enabling kubelet service..."
  systemctl enable kubelet >/dev/null
  ok "kubelet service enabled"
}
