# RBAC Security Validation Report

This report documents the strict security boundaries enforced for the `nginx-deployer` user.

## 1. Identity Provisioning
*   **User:** `nginx-deployer`
*   **Authentication:** X.509 Client Certificate (signed by the Kubernetes Cluster CA)
*   **Mechanism:** Native Kubernetes Certificate Signing Request (CSR) pipeline
*   **Namespace:** `nginx-app`

## 2. Granted Permissions
The user is restricted to managing the application lifecycle within the `nginx-app` namespace. They have explicit access to:
*   Deployments and Deployments/Scale (apps)
*   Services, Pods, ConfigMaps (core)
*   Ingresses and Ingresses/Status (networking.k8s.io)
*   Secrets (read-only metadata)

## 3. Active Security Boundary Tests
| Action | Status | Notes |
| :--- | :--- | :--- |
| `kubectl get pods -n nginx-app` | ✅ Success | Explicitly granted namespace access |
| `kubectl scale deployment nginx-deployment -n nginx-app --replicas=3` | ✅ Success | Scale subresource permission granted |
| `kubectl get nodes` | ❌ Forbidden | No cluster-scope read access |
| `kubectl create namespace forbidden-ns` | ❌ Forbidden | No cluster-scope write access |
| `kubectl run sneaky-pod --image=nginx -n kube-system` | ❌ Forbidden | Restricted by namespace-scoped RoleBinding |
| `kubectl get secrets -n nginx-app` (ls) | ✅ Success | Metadata access only (private keys remain encrypted) |
