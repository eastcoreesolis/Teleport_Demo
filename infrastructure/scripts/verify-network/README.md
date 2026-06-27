# verify-network

Validates the network configuration of the 3 K8s cluster nodes **before**
kubeadm is installed. Confirms that:

- All nodes are reachable via SSH
- DNS resolves each hostname
- eth0 (internal) and eth1 (external) have the correct IPs
- The default route is on eth1, not eth0
- Internal cross-node ping works
- eth0 has no internet egress, eth1 does

## Usage

```bash
# Run the full verification (interactive)
./verify-network.sh

# List all available checks
./verify-network.sh --list

# Run a single check (must have all required env vars pre-set)
./verify-network.sh --check connectivity

