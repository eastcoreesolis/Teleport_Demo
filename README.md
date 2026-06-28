# Command Instructions

## Setup your Virtual Machines

Refer to: **Teleport_Demo/infrastructure/vm-setup.md**

## Setup Kubernetes

### Control Plane Step 1

Log into or ssh into your designated Control Plane (Control Node)

#### 1. Generate your ED25519 key pair (if not already present in the snapshot)
```bash
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
```

#### 2. Copy the keys to all nodes (external IPs) to authorize passwordless SSH
```bash
ssh-copy-id -i ~/.ssh/id_ed25519 esolis@<control node internal ip addr>
```

```bash
ssh-copy-id -i ~/.ssh/id_ed25519 esolis@<worker node x internal ip addr>
```

```bash
ssh-copy-id -i ~/.ssh/id_ed25519 esolis@<worker node x internal ip addr>
```

#### 3. Ensure the git repository is cloned into your home directory on all three nodes
#### (Run this on kcontrol, kworker1, and kworker2)

```bash
git clone https://github.com/your-username/Teleport_Demo.git ~/Teleport_Demo
```

### All Nodes Step 1

#### 1. Run the prepare-network.sh script on all nodes

```bash
cd ~/Teleport_Demo/infrastructure/scripts
```

```bash
sudo ./prepare-network/prepare-network.sh
```

### Control Plane Step 2

#### 1. Run the prepare-network.sh script o

```bash
cd ~/Teleport_Demo/infrastructure/scripts
```

```bash
sudo ./verify-network/verify-network.sh
```

### All Nodes Step 2

#### 1. Run the kubeadm-install.sh script on all nodes

```bash
cd ~/Teleport_Demo/infrastructure/scripts
```

```bash
sudo ./verify-network/kubeadm-install.sh
```

### Control Plane Step 3

#### 1. Run kubeadm init using sudo

```bash
sudo kubeadm init \
  --apiserver-advertise-address=<control node internal ip addr> \
  --pod-network-cidr=192.168.0.0/16 \
  --node-name=kcontrol
```

### Control Plane Step 4

#### 1. Run the bootstrap-control-plane.sh script on the control node

```bash
cd ~/Teleport_Demo/infrastructure/scripts
```

```bash
sudo ./verify-network/bootstrap-control-plane.sh
```

```bash
sudo kubeadm init \
  --apiserver-advertise-address=<control node internal ip addr> \
  --pod-network-cidr=192.168.0.0/16 \
  --node-name=kcontrol
```

Copy the **kubeadm join** command for use in the next step.

### Worker Nodes  Step 1

#### 1. Configure kubelet and join the worker nodes to the cluster.

```bash
echo 'KUBELET_EXTRA_ARGS="--node-ip=<worker node x internal ip addr>"' | sudo tee /etc/default/kubelet
```

```bash
kubeadm join 192.168.2.25:6443 --token <your token> \
        --discovery-token-ca-cert-hash sha256:<your hash>
```
### Control Plane Step 5

#### 1. Verify that all nodes are online, healthy and communicating over the internal network

```bash
kubectl get nodes -o wide
```

```bash
kubectl get pods -n calico-system
```

#### 2. Test the cluster

```bash
kubectl run network-test-1 --image=alpine --overrides='{"spec": {"nodeName": "<target worker node 1 hostname>"}}' -- sh -c "sleep 3600"
```

```bash
kubectl run network-test-2 --image=alpine --overrides='{"spec": {"nodeName": "<target worker node 2 hostname>"}}' -- sh -c "sleep 3600"
```

```bash
POD2_IP=$(kubectl get pod network-test-2 -o jsonpath='{.status.podIP}')
```

```bash
echo "Target Pod IP on kworker2: $POD2_IP"
```

```bash
kubectl exec network-test-1 -- ping -c 3 "$POD2_IP"
```

Expected output:

```text
PING 192.168.77.129 (192.168.77.129): 56 data bytes
64 bytes from xxx.xxx.xxx.xxx: seq=0 ttl=62 time=0.xxx ms
64 bytes from xxx.xxx.xxx.xxx: seq=0 ttl=62 time=0.xxx ms
64 bytes from xxx.xxx.xxx.xxx: seq=0 ttl=62 time=0.xxx ms

--- xxx.xxx.xxx.xxx ping statistics ---
3 packets transmitted, 3 packets received, 0% packet loss
round-trip min/avg/max = 0.xxx/0.xxx/0.xxx ms
```

If you recieve the expected output, our cluster is successfully deployed.
To clean up the test, run the following command:

```bash
kubectl delete pod network-test-1 network-test-2
```















