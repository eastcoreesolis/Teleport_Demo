# kubeadm-install/03-kubetools.sh
# ============================================================================
#  Phase 3: Install Kubernetes toolchain (kubeadm, kubelet, kubectl)
# ============================================================================

source "${SCRIPT_DIR}/lib/version-pinning.sh"

install_kubetools() {
  section "Phase 3 of 4 — Kubernetes Toolchain"
  echo ""

  echo -e "  ${CYN}→${NC} Adding official Kubernetes APT repository (${KUBERNETES_REPO_VERSION})..."
  curl -fsSL "https://pkgs.k8s.io/core:/stable:/${KUBERNETES_REPO_VERSION}/deb/Release.key" | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg --yes
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBERNETES_REPO_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list >/dev/null

  echo -e "  ${CYN}→${NC} Refreshing APT cache..."
  apt-get update -y >/dev/null

  echo -e "  ${CYN}→${NC} Installing kubelet, kubeadm, and kubectl (${K8S_VERSION})..."
  apt-get install -y kubelet="${K8S_VERSION}" kubeadm="${K8S_VERSION}" kubectl="${K8S_VERSION}" >/dev/null

  # Pin versions to protect them against automatic updates
  apt-mark hold kubelet kubeadm kubectl
  ok "Packages successfully installed and pinned"

  echo -e "  ${CYN}→${NC} Enabling kubelet service on startup..."
  systemctl enable kubelet >/dev/null
  ok "kubelet service enabled"
}
