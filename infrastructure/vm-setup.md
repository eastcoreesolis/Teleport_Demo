# Phase 1.0 — Virtual Machine Provisioning

This document outlines the virtual machine topology, hardware requirements, and network mapping required to build the 3-node Kubernetes cluster. Follow these specifications exactly before running any setup scripts.

---

## 1. Node Specifications

You must provision **three (3) virtual machines** running a fresh, clean install of **Ubuntu Server 22.04 LTS (Jammy Jellyfish)**.

| Hostname | Role | vCPU | RAM | OS Disk |
| :--- | :--- | :--- | :--- | :--- |
| **`kcontrolplane`** | Control Plane | 2 | 4 GB | 20 GB+ |
| **`kworkera`** | Worker Node | 2 | 4 GB | 20 GB+ |
| **`kworkerb`** | Worker Node | 2 | 4 GB | 20 GB+ |

---

## 2. Network Adapter Mapping (Dual-NIC)

Each VM **must** be configured with exactly **two (2) Network Interface Cards (NICs)**. They must map logically to the host operating system interfaces in the following order:

### Interface 1 (`eth0`) — Isolated Cluster Network
* **Purpose:** All internal Kubernetes traffic (Control Plane API, Pod network overlay, etcd consensus, Kubelet-to-API communication).
* **Network Profile:** Private / Internal-only switch. No routing to the Internet. No DHCP.
* **IP Allocation Pattern:** Static `192.168.2.x/24` subnet.

### Interface 2 (`eth1`) — Management & Egress Network
* **Purpose:** Node administration, SSH, package installation (`apt`), external ingress controllers, and Internet egress.
* **Network Profile:** External / Bridged switch with NAT or direct LAN routing.
* **Gateway & DNS:** This interface holds the default gateway and upstream DNS configuration.
* **IP Allocation Pattern:** Static `192.168.1.x/24` subnet.

---

## 3. Network Topology Schema

Ensure your hypervisor network routing matches the following structural pattern:

```text
               [ Internet / External LAN (192.168.1.0/24) ]
                                    │
          ┌─────────────────────────┼─────────────────────────┐
          │ (eth1)                  │ (eth1)                  │ (eth1)
   ┌──────────────┐          ┌──────────────┐          ┌──────────────┐
   │kcontrolplane │          │   kworkera   │          │   kworkerb   │
   └──────────────┘          └──────────────┘          └──────────────┘
          │ (eth0)                  │ (eth0)                  │ (eth0)
          └─────────────────────────┴─────────────────────────┘
               [ Isolated Private Cluster Network (192.168.2.0/24) ]
```

---

## 4. Operating System Configuration Requirements

### Static IP Target Table

Using the table below as a guide, during VM operating system installation, configure the network interfaces statically or let the `prepare-network.sh` script guide you to a static configuration matching the layout shown below.

| Hostname       | eth0 IP (Internal) | eth1 IP (External) | Default Gateway (eth1) |
|----------------|-------------------|-------------------|------------------------|
| `kcontrolplane` | `192.168.2.85/24` | `192.168.1.85/24` | `192.168.1.254` (or your local gateway) |
| `kworkera`      | `192.168.2.86/24` | `192.168.1.86/24` | `192.168.1.254` (or your local gateway) |
| `kworkerb`      | `192.168.2.87/24` | `192.168.1.87/24` | `192.168.1.254` (or your local gateway) |

### Operating System Configuration Requirements

During the Ubuntu installation wizard, enforce the following settings:

- **System Hostnames:** Use `kcontrolplane`, `kworkera`, and `kworkerb` precisely (all lowercase).
- **Administrative User:** Create a primary administrator account with root privileges (for example, `admin`).
- **SSH Server:** Enable the OpenSSH Server during installation. Do not install any snap packages such as MicroK8s or Docker.
- **Clean Root Access:** Ensure your user account is added to the sudoers file with either passwordless escalation or standard password authorization.

---

## 5. Post-Provisioning Checklist

Before running the automated script suites, ensure you complete the following manual steps.

### A. Establish SSH Keys

From your local workstation or the control plane node, generate an SSH key pair and copy the public key to all cluster nodes to enable passwordless administrative access:

```bash
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519

ssh-copy-id <userID>@192.168.1.85
ssh-copy-id <userID>@192.168.1.86
ssh-copy-id <userID>@192.168.1.87
```

### B. Clone the Repository

Clone the project repository onto each of the three nodes in the user's home directory:

```bash
git clone https://github.com/eastcoreesolis/Teleport_Demo.git ~/Teleport_Demo
```
