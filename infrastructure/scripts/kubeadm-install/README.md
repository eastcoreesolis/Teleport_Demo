# kubeadm-install

Installs the container runtime (`containerd`) and the Kubernetes control plane toolchain (`kubeadm`, `kubelet`, `kubectl`) pinned to specific stable releases.

## Supported OS
- **Ubuntu 22.04 LTS (Jammy Jellyfish)** strictly. This script is optimized for Jammy kernel dependencies and repository structures.

## Usage

Run this script with root privileges on **each of the 3 nodes** before attempting to bootstrap the cluster with `kubeadm init`:

```bash
sudo ./kubeadm-install.sh
