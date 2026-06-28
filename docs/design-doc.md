# Architecture & Design Document: Secure GitOps Sandbox

This document outlines the architectural decisions, networking topologies, security configurations, and failure mode analysis for the 3-node secure Kubernetes cluster.

## 1. System Topology Overview

The cluster consists of three nodes utilizing a dual-network interface card (NIC) setup to isolate administrative control traffic from internal pod and service communication:

```text
               +--------------------------------------+
               |          External Workstation        |
               +------------------+-------------------+
                                  |
                            Hosts: argocd.local (External IP)
                                  |
                                  v  Port 443 / 80
+---------------------------------+------------------------------------------+
|  Node: kcontrolplane (Control Plane)                                       |
|                                                                            |
|  +------------------+    +------------------+                              |
|  | eth0 (External)  |    | eth1 (Internal)  | [192.168.2.25]               |
|  | Management / SSH |    | Control Plane IP |                              |
|  +------------------+    +--------+---------+                              |
|                                   |                                        |
+-----------------------------------|----------------------------------------+
                                    |
            +-----------------------+-----------------------+
            | (Internal Private Switch / Network)           |
            |                                               |
+-----------v---------------------+           +-------------v--------------+
| Node: kworkera (Worker A)       |           | Node: kworkerb (Worker B)  |
|                                 |           |                            |
| eth1: [192.168.2.86]            |           | eth1: [192.168.x.x]        |
| Pod CIDR: 192.168.77.0/24       |           | Pod CIDR: 192.168.x.x      |
|                                 |           |                            |
| +-----------------------------+ |           |                            |
| | Pod: ingress-nginx-cont.    | |           |                            |
| | (hostNetwork: true)         | |           |                            |
| | Binds to Host Port 443      | |           |                            |
| +-----------------------------+ |           |                            |
+---------------------------------+           +----------------------------+
```

### Node Specifications
*   **1 x Control Plane (`kcontrolplane`):** Runs Kubernetes control components, API server, and ArgoCD repository servers.
*   **2 x Worker Nodes (`kworkera`, `kworkerb`):** Hosts workload pods (`nginx-deployment`) and infrastructure components (such as `ingress-nginx-controller`).

---

## 2. Network Design & Dual-NIC Isolation

Strict network isolation is enforced through two distinct physical/virtual interfaces on all nodes:

1.  **`eth0` (External Network):** Reserved strictly for out-of-band management, SSH access, and initial cluster provisioning. No cluster control plane communication (e.g., `etcd`, `kube-apiserver` traffic) is exposed on this interface.
2.  **`eth1` (Internal Cluster Network):** Used exclusively for node-to-node routing, Kubernetes API server advertisements, overlay pod traffic (via Calico), and internal service discovery.

### IP Forwarding and Calico CNI
*   **Routing Integrity:** `prepare-network.sh` configures static interface routes ensuring that cluster traffic never leaks to the public `eth0` interface.
*   **CNI Selection:** Project Calico is used to manage the pod network overlay. It encapsulates pod traffic over the internal `eth1` interfaces, ensuring complete isolation of workload execution environments from external networks.

### CoreDNS and Dual-NIC Constraints
During cluster execution, the dual-NIC architecture creates a DNS resolving constraint. By default, CoreDNS forwards unknown upstream queries to the local nodes' `/etc/resolv.conf`. In an isolated dual-NIC environment:
*   Local node upstream configuration might point to resolvers unreachable over the internal interface.
*   The pod network overlay IP blocks are not NAT'ed externally by default.

**Design Resolution:** CoreDNS is patched globally to bypass stale upstream file pointers, directly forwarding public domain checks (such as `github.com`) to external public resolvers (`8.8.8.8`, `1.1.1.1`) over an established NAT gateway or routing point on `eth0`.

---

## 3. Security Posture & RBAC Boundary

This cluster enforces strict multitenancy through a programmatic Certificate Signing Request (CSR) workflow.

### The RBAC Model
Access is bounded strictly to the `nginx-app` namespace for the tenant `nginx-deployer`:

```yaml
rules:
- apiGroups: ["apps", ""]
  resources: ["deployments", "services", "pods", "configmaps"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
```

### Cryptographic Identity Management
1.  **CSR Workflow:** Instead of distributing admin-level service account tokens or master credentials, users must generate a local private RSA key and submit a standard Kubernetes `CertificateSigningRequest`.
2.  **Cluster Sign-off:** The administrator approves the CSR, and the internal CA signs the user's certificate.
3.  **Scoped Context:** The generated client certificate is embedded directly into a targeted `kubeconfig` with the context restricted to the user's tenant namespace.

---

## 4. Continuous Delivery & GitOps Architecture

The application configuration state is completely declarative and controlled via ArgoCD.

### Reconciliation and Conflict Mitigation
*   **Stale Metadata Pruning:** When importing manual manifests into a GitOps repo, metadata fields like `resourceVersion`, `uid`, and `creationTimestamp` must be stripped. If kept, the Kubernetes API rejects ArgoCD's patch requests with `Resource Modified` conflicts.
*   **Bare-Metal Ingress Handling:** In cloud environments, Ingresses remain in `Progressing` until an external cloud load-balancer assigns them a dynamic IP. In bare-metal clusters, this field remains empty. We implement a custom Lua health customization in the `argocd-cm` ConfigMap to prevent Ingresses from being marked as `Progressing` indefinitely:
    ```lua
    hs = {}
    hs.status = "Healthy"
    hs.message = "Ingress is OK"
    return hs
    ```

---

## 5. Failure Domains & Mitigation Strategies

| Failure Scenario | Impact | Built-in Mitigation |
| :--- | :--- | :--- |
| **Worker Node Loss** | Pods scheduled on the lost node go offline. | Kubernetes automatically reschedules deployment replicas to the remaining worker node. |
| **Ingress Controller Failure** | External domain access (`argocd.local`, `nginx.local`) drops. | Running the Ingress deployment with host-network port binding allows simple node-port recovery and local DNS target redirection. |
| **Git Repository Offline** | ArgoCD cannot synchronize new commits. | The cluster continues running the last applied state with zero downtime. Local state is drift-protected via self-healing once the repo recovers. |




