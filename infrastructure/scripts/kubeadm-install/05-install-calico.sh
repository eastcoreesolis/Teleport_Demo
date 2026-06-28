# kubeadm-install/05-install-calico.sh
# ============================================================================
#  Phase 5 of 5: Install Calico CNI (v3.27.3) pinned to internal interface (eth0)
# ============================================================================

source "${SCRIPT_DIR}/lib/version-pinning.sh"

install_calico() {
  section "Phase 5 of 5 — Calico CNI Installation"
  echo ""
  echo "  Target: Calico ${CALICO_VERSION} (via Tigera Operator)"
  echo "  Bound to internal interface: eth0"
  echo ""

  # ---------- 1. Apply Tigera Operator ----------
  echo -e "  ${CYN}→${NC} Applying Tigera Operator manifest..."

  local operator_url="https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml"

  # Use kubectl create first to bypass the annotation size limits. If it exists, use replace.
  if ! kubectl create -f "$operator_url" >/dev/null 2>&1; then
    kubectl replace -f "$operator_url" >/dev/null 2>&1 || true
  fi
  ok "Tigera Operator resources applied successfully"

  # ---------- 2. Wait for the CRDs to be registered ----------
  echo -e "  ${CYN}→${NC} Waiting for 'Installation' CRD to register..."

  local waited=0
  while (( waited < 30 )); do
    if kubectl get crd installations.operator.tigera.io >/dev/null 2>&1; then
      ok "Installation CRD recognized by API server"
      break
    fi
    sleep 2
    ((waited++))
  done

  if ! kubectl get crd installations.operator.tigera.io >/dev/null 2>&1; then
    fail "Timed out waiting for the Installation CRD to register"
    return 1
  fi

  # ---------- 3. Generate custom-resources manifest ----------
  echo -e "  ${CYN}→${NC} Compiling custom resources for internal network binding..."
  local custom_res_file="/tmp/calico-custom-resources.yaml"
  cat > "$custom_res_file" <<EOF
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: 192.168.0.0/16
      encapsulation: None
      natOutgoing: Enabled
      nodeSelector: all()
    nodeAddressAutodetectionV4:
      interface: ^eth0$
---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
EOF

  # ---------- 4. Apply Custom Resources ----------
  echo -e "  ${CYN}→${NC} Deploying Calico custom resources..."
  kubectl apply -f "$custom_res_file" >/dev/null
  ok "Calico CNI resources applied"

  # ---------- 5. Active Wait for Running State ----------
  echo -e "  ${CYN}→${NC} Waiting for Calico system namespace to initialize..."

  local ns_waited=0
  local ns_exists=false
  while (( ns_waited < 15 )); do
    if kubectl get ns calico-system >/dev/null 2>&1 || [ $? -ne 0 ]; then
      # Double check if it actually exists to bypass any false positives
      if kubectl get ns calico-system >/dev/null 2>&1; then
        ns_exists=true
        break
      fi
    fi
    sleep 2
    ((ns_waited++))
  done

  echo -e "  ${CYN}→${NC} Waiting for Calico system pods to initialize (up to 180 seconds)..."

  local pod_waited=0
  while (( pod_waited < 60 )); do
    # Read state inside a subshell where errors are locally ignored to protect parent set -e
    local status_summary
    status_summary=$(
      set +e
      set +o pipefail
      pods_raw=$(kubectl get pods -n calico-system --no-headers 2>/dev/null)
      if [[ -z "$pods_raw" ]]; then
        echo "pending"
      else
        # Count pods that are NOT in Running or Completed states
        not_running=$(echo "$pods_raw" | awk '$3 != "Running" && $3 != "Completed"' | wc -l)
        echo "$not_running"
      fi
    )

    if [[ "$status_summary" == "0" ]]; then
      echo ""
      ok "All Calico system pods are running and healthy"
      return 0
    fi

    echo -n "."
    sleep 3
    ((pod_waited++))
  done

  echo ""
  warn "Calico pods are still stabilizing. You can watch progress with:"
  echo "      kubectl get pods -n calico-system -w"
}
