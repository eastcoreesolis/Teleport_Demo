# kubeadm-install/lib/version-pinning.sh
# ============================================================================
#  Centralized version pinning — Optimized strictly for Ubuntu 22.04 (Jammy)
# ============================================================================

# Target versions
K8S_BASE_VERSION="1.29.5"
CONTAINERD_BASE_VERSION="1.7.22"  # Updated to a stable, existing version
KUBERNETES_REPO_VERSION="v1.29"

# Exact target strings (fallback variables)
K8S_VERSION="1.29.5-1.1"
CONTAINERD_VERSION="1.7.22-1"

# Dynamically extracts the exact string matching our target versions
resolve_package_versions() {
  # 1. Query local cache for the target containerd version
  local resolved_containerd
  resolved_containerd=$(apt-cache madison containerd.io 2>/dev/null | grep "${CONTAINERD_BASE_VERSION}" | head -n1 | awk '{print $3}')
  
  if [[ -n "$resolved_containerd" ]]; then
    CONTAINERD_VERSION="$resolved_containerd"
  else
    # Fallback to the latest available 1.7.x if our target isn't in Docker's active pool
    resolved_containerd=$(apt-cache madison containerd.io 2>/dev/null | grep "1.7." | head -n1 | awk '{print $3}')
    if [[ -n "$resolved_containerd" ]]; then
      CONTAINERD_VERSION="$resolved_containerd"
    fi
  fi

  # 2. Query local cache for the target Kubernetes version
  local resolved_k8s
  resolved_k8s=$(apt-cache madison kubeadm 2>/dev/null | grep "${K8S_BASE_VERSION}" | head -n1 | awk '{print $3}')
  if [[ -n "$resolved_k8s" ]]; then
    K8S_VERSION="$resolved_k8s"
  fi
}
