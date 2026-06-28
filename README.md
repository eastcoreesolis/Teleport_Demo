# Teleport Demo: Installation Guide

This guide walks you through setting up a 3-node Kubernetes cluster, configuring strict RBAC, and bootstrapping a full GitOps workflow with ArgoCD.

## 1. Virtual Machine Setup

Refer to the VM provisioning guide: [infrastructure/vm-setup.md](infrastructure/vm-setup.md).

## 2. Control Plane: SSH Key Generation

Log in to your designated Control Plane node.

### 2.1. Generate an ED25519 Key Pair (if not already present)

```bash
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
```

### 2.2. Authorize Passwordless SSH to All Nodes

Copy the public key to the external IP of the control plane and every worker node.

```bash
ssh-copy-id -i ~/.ssh/id_ed25519 <username>@<control-plane-external-ip>
```

```bash
ssh-copy-id -i ~/.ssh/id_ed25519 <username>@<worker-1-external-ip>
```

```bash
ssh-copy-id -i ~/.ssh/id_ed25519 <username>@<worker-2-external-ip>
```

## 3. All Nodes: Repository Setup

### 3.1. Clone the Repository

Ensure the repository is cloned into your home directory on all three nodes.

```bash
git clone https://github.com/<your-github-username>/Teleport_Demo.git ~/Teleport_Demo
```

## 4. All Nodes: Network Preparation

### 4.1. Run the Network Preparation Script

This script configures the dual-NIC isolation, routing rules, and IP forwarding required for the cluster.

```bash
cd ~/Teleport_Demo/infrastructure/scripts
sudo ./prepare-network/prepare-network.sh
```

## 5. Control Plane: Network Verification

### 5.1. Verify Network Isolation and Routing

Run the verification script to ensure the node can reach both the external and pod networks.
**do not run as root**

```bash
cd ~/Teleport_Demo/infrastructure/scripts
./verify-network/verify-network.sh
```

## 6. All Nodes: Kubernetes Installation

### 6.1. Install kubeadm, kubelet, and kubectl

```bash
cd ~/Teleport_Demo/infrastructure/scripts
sudo ./kubeadm-install/kubeadm-install.sh
```

## 7. Control Plane: Cluster Initialization

### 7.1. Initialize the Control Plane

```bash
sudo kubeadm init \
  --apiserver-advertise-address=<control-plane-internal-ip> \
  --pod-network-cidr=192.168.0.0/16 \
  --node-name=kcontrol
```

### 7.2. Bootstrap the Control Plane

This configures `kubectl` for the `root` user, installs the Calico CNI, and applies CoreDNS customizations.

```bash
cd ~/Teleport_Demo/infrastructure/scripts
sudo ./kubeadm-install/bootstrap-control-plane.sh
```

> **Note:** Copy the `kubeadm join` command output at the end of this step. You will need it for the worker nodes.

## 8. Worker Nodes: Cluster Join

Run these steps on **each** worker node.

### 8.1. Configure kubelet

Set the kubelet to advertise the node's internal IP.

```bash
echo 'KUBELET_EXTRA_ARGS="--node-ip=<worker-internal-ip>"' | sudo tee /etc/default/kubelet
```

### 8.2. Join the Cluster

```bash
sudo kubeadm join <control-plane-internal-ip>:6443 \
  --token <your-token> \
  --discovery-token-ca-cert-hash sha256:<your-hash>
```

## 9. Control Plane: Cluster Validation

### 9.1. Verify Node Status

Ensure all nodes are `Ready`.

```bash
kubectl get nodes -o wide
```

### 9.2. Verify Calico Pods

Ensure all Calico components are running.

```bash
kubectl get pods -n calico-system
```

### 9.3. Test Pod-to-Pod Networking

Deploy two test pods on different worker nodes and verify they can ping each other.

```bash
kubectl run network-test-1 --image=alpine --overrides='{"spec": {"nodeName": "<worker-1-hostname>"}}' -- sh -c "sleep 3600"

kubectl run network-test-2 --image=alpine --overrides='{"spec": {"nodeName": "<worker-2-hostname>"}}' -- sh -c "sleep 3600"

POD2_IP=$(kubectl get pod network-test-2 -o jsonpath='{.status.podIP}')

echo "Target Pod IP on worker-2: $POD2_IP"

kubectl exec network-test-1 -- ping -c 3 "$POD2_IP"
```

**Expected Output:**

```text
PING 192.168.77.129 (192.168.77.129): 56 data bytes
64 bytes from xxx.xxx.xxx.xxx: seq=0 ttl=62 time=0.xxx ms
64 bytes from xxx.xxx.xxx.xxx: seq=0 ttl=62 time=0.xxx ms
64 bytes from xxx.xxx.xxx.xxx: seq=0 ttl=62 time=0.xxx ms

--- xxx.xxx.xxx.xxx ping statistics ---
3 packets transmitted, 3 packets received, 0% loss
```

Clean up the test pods:

```bash
kubectl delete pod network-test-1 network-test-2
```

## 10. Control Plane: RBAC with Certificate Signing Requests (CSR)

### 10.1. Install cert-manager

```bash
kubectl create -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.2/cert-manager.yaml || kubectl replace -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.2/cert-manager.yaml
```

Wait for all cert-manager pods to be `1/1 Running`:

```bash
kubectl get pods -n cert-manager -w
```

### 10.2. Create a Self-Signed ClusterIssuer

```bash
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
EOF
```

### 10.3. Generate a Private Key for a New User

Generate a 2048-bit RSA key for a new user, `nginx-deployer`:

```bash
openssl genrsa -out ~/nginx-deployer.key 2048
```

### 10.4. Create the Kubernetes RBAC Role and RoleBinding

```bash
kubectl create namespace nginx-app

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: nginx-app
  name: nginx-deployer-role
rules:
- apiGroups: ["apps", ""]
  resources: ["deployments", "services", "pods", "configmaps"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: nginx-deployer-binding
  namespace: nginx-app
subjects:
- kind: User
  name: nginx-deployer
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: nginx-deployer-role
  apiGroup: rbac.authorization.k8s.io
EOF
```

### 10.5. Generate the Certificate Signing Request (CSR) Manifest

```bash
openssl req -new -key ~/nginx-deployer.key -out ~/nginx-deployer.csr -subj "/CN=nginx-deployer"

cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: nginx-deployer-csr
spec:
  request: $(cat ~/nginx-deployer.csr | base64 | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages:
  - client auth
EOF
```

### 10.6. Approve the CSR and Extract the Signed Certificate

```bash
kubectl certificate approve nginx-deployer-csr

kubectl get csr nginx-deployer-csr -o jsonpath='{.status.certificate}' | base64 -d > ~/nginx-deployer.crt
```

### 10.7. Create the User's kubeconfig

```bash
HOME_DIR=/home/<your-username>

kubectl config set-credentials nginx-deployer \
  --client-certificate=${HOME_DIR}/nginx-deployer.crt \
  --client-key=${HOME_DIR}/nginx-deployer.key \
  --embed-certs=true

kubectl config set-context nginx-deployer-context \
  --cluster=kubernetes \
  --user=nginx-deployer \
  --namespace=nginx-app
```

### 10.8. Deploy the Nginx Application

Switch to the restricted user context:

```bash
kubectl config use-context nginx-deployer-context
```

Apply the manifests:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: nginx
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.25.3
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  selector:
    app: nginx
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
  type: ClusterIP
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
  annotations:
    cert-manager.io/cluster-issuer: selfsigned-issuer
spec:
  rules:
  - host: nginx.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx-service
            port:
              number: 80
  tls:
  - hosts:
    - nginx.local
    secretName: nginx-tls-secret
EOF
```

### 10.9. Verify the Workload

Check that the Pods are running:

```bash
kubectl get pods -n nginx-app
```

Switch back to the admin context to inspect the certificate status:

```bash
kubectl config use-context kubernetes-admin@kubernetes
kubectl get certificate -n nginx-app
```

### 10.10. RBAC Boundary Validation

**Positive Test (Allowed Actions):**

```bash
kubectl config use-context nginx-deployer-context
kubectl get pods -n nginx-app
kubectl scale deployment nginx-deployment -n nginx-app --replicas=3
kubectl get pods -n nginx-app
kubectl scale deployment nginx-deployment -n nginx-app --replicas=2
```

**Negative Test 1 (Internal Boundary):**

```bash
kubectl config use-context kubernetes-admin@kubernetes
kubectl create namespace forbidden-ns

kubectl config use-context nginx-deployer-context
kubectl run sneaky-pod --image=nginx -n forbidden-ns
# Expected: Error from server (Forbidden): pods is forbidden
```

**Negative Test 2 (Cluster Boundary):**

```bash
kubectl get nodes
# Expected: Error from server (Forbidden)

kubectl get secrets -n nginx-app
# Expected: Error from server (Forbidden)
```

## 11. Control Plane: GitOps Preparation

### 11.1. Create the GitOps Folder Structure

```bash
mkdir -p ~/Teleport_Demo/gitops/argocd/apps
```

### 11.2. Generate Declarative Manifests

Export the current running state of the namespace, RBAC, and workloads into YAML files. Use the `--show-managed-fields=false` flag to strip the dynamic fields that cause `resourceVersion` conflicts.

```bash
# Namespace
kubectl get namespace nginx-app -o yaml --show-managed-fields=false > ~/Teleport_Demo/gitops/argocd/apps/00-namespace.yaml

# RBAC
kubectl get role,rolebinding -n nginx-app -o yaml --show-managed-fields=false > ~/Teleport_Demo/gitops/argocd/apps/01-rbac.yaml

# Workloads
kubectl get deployment,service,ingress -n nginx-app -o yaml --show-managed-fields=false > ~/Teleport_Demo/gitops/argocd/apps/02-workloads.yaml
```

### 11.3. Create the ArgoCD Application Manifest

Create the file `~/Teleport_Demo/gitops/argocd/apps/03-argocd-app.yaml` and paste the following content:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<your-github-username>/Teleport_Demo.git
    targetRevision: main
    path: gitops/argocd/apps
  destination:
    server: https://kubernetes.default.svc
    namespace: nginx-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

## 12. Control Plane: ArgoCD Installation

### 12.1. Install ArgoCD

```bash
kubectl create namespace argocd
kubectl create -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.11.0/manifests/install.yaml || kubectl replace -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.11.0/manifests/install.yaml
```

Wait for the core components to come online (up to 3 minutes):

```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=180s
```

### 12.2. Fix CoreDNS to Reach the Internet (GitHub)

Because the cluster uses strict dual-NIC isolation, CoreDNS cannot forward queries to the upstream resolvers. You must manually configure CoreDNS to use public DNS servers directly. This is required for ArgoCD to resolve `github.com`.

```bash
kubectl edit configmap coredns -n kube-system
```

Find the `forward . /etc/resolv.conf` block and replace it with:

```yaml
        forward . 8.8.8.8 1.1.1.1 {
           prefer_udp
           max_concurrent 1000
        }
```

Save and exit, then restart CoreDNS to apply the changes:

```bash
kubectl rollout restart deployment coredns -n kube-system
kubectl rollout status deployment coredns -n kube-system
```

### 12.3. Expose the ArgoCD Web UI

Change the ArgoCD server service to `NodePort` to access it via the control plane's external IP:

```bash
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}'
```

Get the dynamically assigned NodePort:

```bash
ARGOCD_PORT=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[0].nodePort}')
echo "ArgoCD UI is available at: https://192.168.1.25:${ARGOCD_PORT}"
```

Get the initial admin password:

```bash
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "ArgoCD Login Password: ${ARGOCD_PASS}"
```

### 12.4. Register the GitOps Application

```bash
kubectl apply -f ~/Teleport_Demo/gitops/argocd/apps/03-argocd-app.yaml
```

Watch the sync happen:

```bash
kubectl get application -n argocd -w
```

### 12.4.1. Configure Ingress Health Override (Bare-Metal Only)

In bare-metal or sandbox environments, your Ingress resources may not be assigned an external load-balancer IP address automatically. By default, ArgoCD will mark these Ingresses as `Progressing` indefinitely.

To force ArgoCD to evaluate these Ingresses as `Healthy`, apply the following health check override customization:

```bash
kubectl patch configmap argocd-cm -n argocd --type merge -p '
{
  "data": {
    "resource.customizations.health.networking.k8s.io_Ingress": "hs = {}\nhs.status = \"Healthy\"\nhs.message = \"Ingress is OK\"\nreturn hs"
  }
}
'
```

Restart the controller to apply the change:

```bash
kubectl rollout restart statefulset argocd-application-controller -n argocd
```

**Expected Result:** The `nginx-app` application will transition from `OutOfSync` to `Synced` and `Healthy`. This confirms ArgoCD has successfully read the Git repository, pulled the manifests, and deployed them into the `nginx-app` namespace.

## 13. Validate the GitOps Loop

### 13.1. Modify a Manifest in Git

Edit `~/Teleport_Demo/gitops/argocd/apps/02-workloads.yaml` and change the `replicas: 2` line to `replicas: 3`.

### 13.2. Commit and Push

```bash
cd ~/Teleport_Demo
git add .
git commit -m "feat: scale nginx deployment to 3 replicas via gitops"
git push origin main
```

### 13.3. Observe the Automatic Sync

Within a few minutes, ArgoCD will detect the change and scale the deployment to 3 pods. Verify with:

```bash
kubectl get pods -n nginx-app
```

## Appendix A: Natural UI Access via Ingress (Bare-Metal/Dual-NIC)

In environments with strict dual-NIC isolation, accessing services like ArgoCD via random high-port `NodePorts` is cumbersome. You can configure a natural, clean URL mapping (e.g., `https://argocd.local`) by patching the Ingress Controller to bind directly to your host's network interface on port `80` and `443`.

### A.1. Deploy & Patch the NGINX Ingress Controller
Deploy the bare-metal ingress controller and patch its spec to map ports directly to its scheduling node:

Install the controller

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/baremetal/deploy.yaml
```

Wait for the pod to be ready

```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=controller -n ingress-nginx --timeout=120s
```

Patch the deployment to bind to host port 80/443

```bash
kubectl patch deployment ingress-nginx-controller -n ingress-nginx --type json -p '[
  {"op": "add", "path": "/spec/template/spec/hostNetwork", "value": true}
]'
```

Map Domain Names to the Scheduling Node IP

Because the controller runs inside the cluster, it will schedule on a specific host node (often a worker node like kworkera instead of the control plane).

Identify which physical node is running the controller pod:

```bash
kubectl get pods -n ingress-nginx -o wide
```

On your local workstation (physical computer), map this target IP to your local domain routes in your hosts file (/etc/hosts on Linux/macOS, or C:\Windows\System32\drivers\etc\hosts on Windows):

```text
<target-node-ip> argocd.local
<target-node-ip> nginx.local
```

Navigate directly to https://argocd.local or https://nginx.local in your browser. 
All traffic is now routed securely on standard web ports (80/443) through the host-network gateway.


READMEEOF
```
