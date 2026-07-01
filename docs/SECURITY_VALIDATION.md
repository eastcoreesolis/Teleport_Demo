# RBAC Security Validation Report

This report documents the strict security boundaries enforced for the `nginx-deployer` user.

## 1. Identity Provisioning
*   **User:** `nginx-deployer`
*   **Authentication:** X.509 Client Certificate (signed by the Kubernetes Cluster CA)
*   **Mechanism:** Native Kubernetes Certificate Signing Request (CSR) pipeline
*   **Namespace:** `nginx-app`
*   **Source of truth:** `gitops/argocd/apps/01-rbac.yaml`

## 2. Granted Permissions
The user is restricted to managing the application lifecycle within the `nginx-app` namespace. They have explicit access to:
*   Pods, Services, ConfigMaps (core)
*   Deployments and Deployments/Scale (apps)

The user explicitly does **NOT** have access to:
*   Ingresses (the deployer is not authorized to mutate networking)
*   Secrets (no read or metadata access)
*   Cluster-scoped resources (nodes, namespaces, CRDs, etc.)

## 3. Active Security Boundary Tests
| Action | Status | Notes |
| :--- | :--- | :--- |
| `kubectl get pods -n nginx-app` | ✅ Success | Explicitly granted namespace access |
| `kubectl get deployments -n nginx-app` | ✅ Success | `apps/deployments` granted |
| `kubectl scale deployment nginx-deployment -n nginx-app --replicas=3` | ✅ Success | `apps/deployments/scale` subresource granted |
| `kubectl get configmaps -n nginx-app` | ✅ Success | `configmaps` granted |
| `kubectl get services -n nginx-app` | ✅ Success | `services` granted |
| `kubectl get nodes` | ❌ Forbidden | No cluster-scope read access |
| `kubectl create namespace forbidden-ns` | ❌ Forbidden | No cluster-scope write access |
| `kubectl run sneaky-pod --image=nginx -n kube-system` | ❌ Forbidden | Restricted by namespace-scoped RoleBinding |
| `kubectl get ingress -n nginx-app` | ❌ Forbidden | Not granted; networking is platform-team scope |
| `kubectl get secrets -n nginx-app` | ❌ Forbidden | Not granted; secrets are platform-team scope |

## 4. Reproduction
To reproduce the negative tests:
```bash
# Positive (should succeed)
kubectl config use-context nginx-deployer-context
kubectl get pods -n nginx-app
kubectl scale deployment nginx-deployment -n nginx-app --replicas=3
kubectl scale deployment nginx-deployment -n nginx-app --replicas=2

# Negative (should fail with Forbidden)
kubectl config use-context kubernetes-admin@kubernetes
kubectl create namespace forbidden-ns
kubectl config use-context nginx-deployer-context
kubectl run sneaky-pod --image=nginx -n forbidden-ns
kubectl get ingress -n nginx-app
kubectl get secrets -n nginx-app
