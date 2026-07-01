Nginx Application Deployment

This directory contains the manifests for the static Nginx web application, deployed using a Certificate Signing Request (CSR) based identity.

## Architecture
*   **Namespace:** `nginx-app`
*   **User Identity:** `nginx-deployer` (Authenticated via client certificate)
*   **Permissions:** Bound to the `nginx-deployer-role` (Limited to managing Deployments, Services, and Ingresses inside the `nginx-app` namespace only).

## Deployment Files
1.  `manifests/01-namespace.yaml` (Defines the target namespace)
2.  `manifests/02-rbac.yaml` (Defines the strict Role and RoleBinding)
3.  `manifests/03-workloads.yaml` (Defines the Nginx Deployment, Service, and TLS-enabled Ingress)
