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
