# lean quickstart

A single command line quickstart to spin up lean node(s)

### Benefits

- ✅ **Official Tool**: Uses PK's `eth-beacon-genesis` docker tool (not custom tooling)
- ✅ **Complete Genesis State**: Generates full genesis state (JSON + SSZ) plus config files
- ✅ **No hardcoded files** - All genesis files are generated dynamically
- ✅ **Single source of truth** - `validator-config.yaml` defines everything
- ✅ **Easy to modify** - Add/remove nodes by editing `validator-config.yaml`
- ✅ **Standards compliant** - Uses ethpandaops maintained tool

### Requirements

1. Shell terminal: Preferably linux especially if you want to pop out separate new terminals for node
2. Genesis configuration
3. Zeam Build (other clients to be supported soon)
4. **Docker**: Required to run PK's eth-beacon-genesis tool and hash-sig-cli for post-quantum keys
   - Install from: [Docker Desktop](https://docs.docker.com/get-docker/)
5. **yq**: YAML processor for automated configuration parsing
   - Install on macOS: `brew install yq`
   - Install on Linux: See [yq installation guide](https://github.com/mikefarah/yq#install)

## Quick Start

### First Time Setup:
```sh
# 1. Clone the repository
git clone <repo-url>
cd lean-quickstart

# 2. **Run** genesis generation:
./generate-genesis.sh local-devnet/genesis
```

## Scenarios

### Quickly startup various nodes as a local devnet

**Using shell scripts (quick local setup):**
```sh
NETWORK_DIR=local-devnet ./spin-node.sh --node all --generateGenesis --popupTerminal
```

**Using Ansible (recommended for production/remote):**
```sh
./ansible-deploy.sh --node all --network-dir local-devnet --generate-genesis
```
> 📖 See [Ansible Deployment](#ansible-deployment) section or [ansible/README.md](ansible/README.md) for details

### Startup specific nodes only

**Using shell scripts:**
```sh
# Run only zeam_0 and ream_0 nodes (comma-separated)
NETWORK_DIR=local-devnet ./spin-node.sh --node zeam_0,ream_0 --generateGenesis --popupTerminal

# Run only zeam_0 and qlean_0 nodes (space-separated)
NETWORK_DIR=local-devnet ./spin-node.sh --node "zeam_0 qlean_0" --generateGenesis --popupTerminal

# Run only a single node
NETWORK_DIR=local-devnet ./spin-node.sh --node zeam_0 --generateGenesis --popupTerminal
```

**Using Ansible:**
```sh
# Run only zeam_0 and ream_0 nodes
./ansible-deploy.sh --node zeam_0,ream_0 --network-dir local-devnet --generate-genesis

# Run only a single node
./ansible-deploy.sh --node zeam_0 --network-dir local-devnet --generate-genesis
```
  
## Args

1. `NETWORK_DIR` is an env to specify the network directory. Should have a `genesis` directory with genesis config. A `data` folder will be created inside this `NETWORK_DIR` if not already there.
  `genesis` directory should have the following files

    a. `validator-config.yaml` which has node setup information for all the bootnodes
    b. `validators.yaml` which assigns validator indices
    c. `nodes.yaml` which has the enrs generated for each of the respective nodes.
    d. `config.yaml` the actual network config

2. `--generateGenesis` regenerate all genesis files with fresh genesis time and clean data directories
3. `--popupTerminal` if you want to pop out new terminals to run the nodes, opens gnome terminals
4. `--node` specify which node(s) you want to run:
   - Use `all` to run all the nodes in a single go
   - Specify a single node name (e.g., `zeam_0`) to run just that node
   - Use comma-separated node names (e.g., `zeam_0,qlean_0`) to run multiple specific nodes
   - Use whitespace-separated node names (e.g., `"zeam_0 ream_0"`) to run multiple specific nodes
   
   The client is provided this input so as to parse the correct node configuration to startup the node.
5. `--validatorConfig` is the path to specify your nodes `validator-config.yaml`, `validators.yaml` (for which `--node` is still the node key to index) if your node is not a bootnode.
   If unspecified it assumes value of `genesis_bootnode` which is to say that your node config is to be picked from `genesis` folder with `--node` as the node key index.
   This value is further provided to the client so that they can parse the correct config information.

## Genesis Generator

The quickstart includes an automated genesis generator that eliminates the need for hardcoded `validators.yaml` and `nodes.yaml` files.

### Clients supported

Current following clients are supported:

1. Zeam
2. Ream
3. Qlean

However adding a lean client to this setup is very easy. Feel free to do the PR or reach out to the maintainers.

### How It Works

The genesis generator (`generate-genesis.sh`) uses PK's official `eth-beacon-genesis` docker tool to automatically generate:

1. **validators.yaml** - Validator index assignments using round-robin distribution
2. **nodes.yaml** - ENR (Ethereum Node Records) for peer discovery
3. **genesis.json** - Genesis state in JSON format
4. **genesis.ssz** - Genesis state in SSZ format
5. **.key files** - Private key files for each node

**Docker Image**: `ethpandaops/eth-beacon-genesis:pk910-leanchain`  
**Source**: https://github.com/ethpandaops/eth-beacon-genesis/pull/36

### Usage

The genesis generator runs automatically when:
- `validators.yaml` or `nodes.yaml` don't exist, OR
- You use the `--generateGenesis` flag

```sh
# Regenerate genesis files with fresh genesis time
NETWORK_DIR=local-devnet ./spin-node.sh --node all --generateGenesis
```

You can also run the generator standalone:
```sh
./generate-genesis.sh local-devnet/genesis
```

## Hash-Based Signature (Post-Quantum) Validator Keys

This quickstart includes integrated support for **post-quantum secure hash-based signatures** for validator keys. The system automatically generates and manages hash-sig keys during genesis generation.

### How It Works

The genesis generator automatically:
1. **Uses Docker image** `blockblaz/hash-sig-cli:latest` to generate hash-sig keys
2. **Generates hash-sig keys** for N validators (Step 1 of genesis generation)
3. **Stores keys** in `genesis/hash-sig-keys/` directory
4. **Loads keys** automatically when nodes start via environment variables

### Key Generation

When you run the genesis generator, it creates post-quantum secure keys for each validator:

```sh
./generate-genesis.sh local-devnet/genesis
```

**Generated files:**
```
local-devnet/genesis/hash-sig-keys/
├── validator-keys-manifest.yaml    # Metadata for all keys
├── validator_0_pk.json             # Public key for validator 0
├── validator_0_sk.json             # Secret key for validator 0
├── validator_1_pk.json             # Public key for validator 1
├── validator_1_sk.json             # Secret key for validator 1
└── ...                             # Keys for additional validators
```

### Signature Scheme

The system uses the **SIGTopLevelTargetSumLifetime32Dim64Base8** hash-based signature scheme, which provides:

- **Post-quantum security**: Resistant to attacks from quantum computers
- **Active epochs**: 2^18 (262,144 signatures)
- **Total lifetime**: 2^32 (4,294,967,296 signatures)
- **Stateful signatures**: Uses hierarchical signature tree structure

### Configuration

The `validator-config.yaml` file defines the shuffle algorithm, active epoch configuration, and validator specifications:

```yaml
shuffle: roundrobin
config:
  activeEpoch: 18              # Required: Exponent for active epochs (2^18 = 262,144 signatures)
  keyType: "hash-sig"          # Required: Network-wide signature scheme (hash-sig for post-quantum security)
validators:
  - name: "zeam_0"
    privkey: "bdf953adc161873ba026330c56450453f582e3c4ee6cb713644794bcfdd85fe5"
    enrFields:
      ip: "127.0.0.1"
      quic: 9000
    metricsPort: 8080
    count: 1
```

**Required Top-Level Fields:**
- `shuffle`: Validator shuffle algorithm (e.g., `roundrobin`)
- `config.activeEpoch`: Exponent for active epochs used in hash-sig key generation (2^activeEpoch signatures per active period)
- `config.keyType`: Network-wide signature scheme - must be `"hash-sig"` for post-quantum security

**Validator Fields:**
- Hash-sig key files are automatically mapped based on validator position in the array (first validator uses `validator_0_*.json`, second uses `validator_1_*.json`, etc.)

### Key Loading

The `parse-vc.sh` script automatically loads hash-sig keys when starting nodes:

1. Reads `config.keyType` from validator config (network-wide setting)
2. Automatically calculates key index based on validator position in the array
3. Locates corresponding key files in `genesis/hash-sig-keys/`
4. Exports environment variables for client use:
   - `HASH_SIG_PK_PATH`: Path to public key file
   - `HASH_SIG_SK_PATH`: Path to secret key file
   - `HASH_SIG_KEY_INDEX`: Validator's key index (auto-calculated)

**Client Integration:**

Your client implementation should read these environment variables and use the hash-sig keys for validator operations.

### Key Management

#### Key Lifetime

Each hash-sig key has a **finite lifetime** of 2^32 signatures. The keys are structured as:
- **Active epochs**: 2^18 epochs before requiring key rotation
- **Total lifetime**: 2^32 total signatures possible

#### Key Rotation

Hash-based signatures are **stateful** - each signature uses a unique one-time key from the tree. Once exhausted, keys must be rotated:

```sh
# Regenerate all hash-sig keys
./generate-genesis.sh local-devnet/genesis
```

**Warning**: Keep track of signature counts to avoid key exhaustion.

#### Key Security

**Secret keys are highly sensitive:**
- ⚠️ **Never commit** `validator_*_sk.json` files to version control
- ⚠️ **Never share** secret keys
- ✅ **Backup** secret keys in secure, encrypted storage
- ✅ **Restrict permissions** on key files (e.g., `chmod 600`)

The `.gitignore` should already exclude hash-sig keys:
```
local-devnet/genesis/hash-sig-keys/
```

### Verifying Keys

The manifest file (`validator-keys-manifest.yaml`) contains metadata about all generated keys:

```yaml
# Hash-Sig Validator Keys Manifest
# Generated: 2024-01-15T10:30:00Z

scheme: "SIGTopLevelTargetSumLifetime32Dim64Base8"
activeEpochs: 262144  # 2^18
totalLifetime: 4294967296  # 2^32
validatorCount: 3

validators:
  - index: 0
    publicKey: "validator_0_pk.json"
    secretKey: "validator_0_sk.json"
  - index: 1
    publicKey: "validator_1_pk.json"
    secretKey: "validator_1_sk.json"
  # ... additional validators
```

### Troubleshooting

**Problem**: Hash-sig keys not loading during node startup
```
Warning: Hash-sig public key not found at genesis/hash-sig-keys/validator_0_pk.json
```

**Solution**: Run the genesis generator to create keys:
```sh
./generate-genesis.sh local-devnet/genesis
```

---

**Problem**: Hash-sig key file not found
```
Warning: Hash-sig secret key not found at genesis/hash-sig-keys/validator_5_sk.json
```

**Solution**: This usually means you have more validators configured than hash-sig keys generated. Regenerate genesis files:
```sh
./generate-genesis.sh local-devnet/genesis
```

## Automation Features

This quickstart includes automated configuration parsing:

- **Official Genesis Generation**: Uses PK's `eth-beacon-genesis` docker tool from [PR #36](https://github.com/ethpandaops/eth-beacon-genesis/pull/36)
- **Complete File Set**: Generates `validators.yaml`, `nodes.yaml`, `genesis.json`, `genesis.ssz`, and `.key` files
- **QUIC Port Detection**: Automatically extracts QUIC ports from `validator-config.yaml` using `yq`
- **Node Detection**: Dynamically discovers available nodes from the validator configuration
- **Private Key Management**: Automatically extracts and creates `.key` files for each node
- **Error Handling**: Provides clear error messages when nodes or ports are not found

The system reads all configuration from YAML files, making it easy to add new nodes or modify existing ones without changing any scripts.

## Ansible Deployment

The repository now includes Ansible-based deployment for enhanced automation, remote deployment capabilities, and better infrastructure management. Ansible provides idempotency, declarative configuration, and support for deploying to multiple remote hosts.

📖 **For detailed Ansible documentation, see [ansible/README.md](ansible/README.md)**

### Ansible Benefits

- ✅ **Remote Deployment**: Deploy nodes to remote servers
- ✅ **Idempotency**: Safe to run multiple times
- ✅ **Infrastructure as Code**: Version-controlled deployment configuration
- ✅ **Multi-Host Support**: Deploy to multiple hosts in parallel
- ✅ **Better State Management**: Track and manage node lifecycle
- ✅ **Extensible**: Easy to add new roles and playbooks

### Installing Ansible

**macOS:**
```sh
brew install ansible
```

**Ubuntu/Debian:**
```sh
sudo apt-get update
sudo apt-get install ansible
```

**Using pip:**
```sh
pip install ansible
```

### Installing Ansible Dependencies

Install required Ansible collections:

```sh
cd ansible
ansible-galaxy install -r requirements.yml
```

### Quick Start with Ansible

**Deploy all nodes with genesis generation:**
```sh
./ansible-deploy.sh --node all --network-dir local-devnet --generate-genesis
```

**Deploy specific nodes:**
```sh
# Single node
./ansible-deploy.sh --node zeam_0 --network-dir local-devnet

# Multiple nodes (comma-separated)
./ansible-deploy.sh --node zeam_0,ream_0 --network-dir local-devnet

# Multiple nodes (space-separated)
./ansible-deploy.sh --node "zeam_0 ream_0" --network-dir local-devnet
```

**Generate genesis files only:**
```sh
./ansible-deploy.sh --playbook genesis.yml --network-dir local-devnet
```

**Deploy with clean data directories:**
```sh
./ansible-deploy.sh --node all --network-dir local-devnet --clean-data --generate-genesis
```

### Ansible Command-Line Options

The `ansible-deploy.sh` wrapper script provides the following options:

| Option | Description | Example |
|--------|-------------|---------|
| `--node NODES` | Nodes to deploy (all, single, or comma/space-separated) | `--node zeam_0,ream_0` |
| `--network-dir DIR` | Network directory | `--network-dir local-devnet` |
| `--generate-genesis` | Force regeneration of genesis files | `--generate-genesis` |
| `--clean-data` | Clean data directories before deployment | `--clean-data` |
| `--validator-config PATH` | Path to validator-config.yaml | `--validator-config custom/path.yaml` |
| `--deployment-mode MODE` | Deployment mode: docker, binary, or kubernetes | `--deployment-mode kubernetes` |
| `--playbook PLAYBOOK` | Ansible playbook to run | `--playbook genesis.yml` |
| `--tags TAGS` | Run only tasks with specific tags | `--tags zeam,genesis` |
| `--check` | Dry run (check mode) | `--check` |
| `--diff` | Show file changes | `--diff` |
| `--verbose` | Verbose output | `--verbose` |

### Ansible Directory Structure

```
ansible/
├── ansible.cfg              # Ansible configuration
├── requirements.yml          # Ansible Galaxy dependencies
├── inventory/
│   ├── hosts.yml            # Host inventory (localhost or remote hosts)
│   └── group_vars/          # Group variables
│       └── all.yml           # Global variables
├── playbooks/
│   ├── site.yml             # Main playbook (genesis + deploy)
│   ├── genesis.yml          # Genesis generation playbook
│   ├── deploy-nodes.yml     # Node deployment playbook
│   └── deploy-single-node.yml # Helper for single node deployment
└── roles/
    ├── common/              # Common setup (Docker, yq, directories)
    ├── genesis/             # Genesis file generation
    ├── zeam/                # Zeam node role
    ├── ream/                # Ream node role
    └── qlean/               # Qlean node role
```

### Remote Deployment

To deploy to remote hosts, update `ansible/inventory/hosts.yml`:

```yaml
all:
  children:
    zeam_nodes:
      hosts:
        zeam_0:
          ansible_host: 192.168.1.10
          ansible_user: ubuntu
          ansible_ssh_private_key_file: ~/.ssh/id_rsa
    ream_nodes:
      hosts:
        ream_0:
          ansible_host: 192.168.1.11
          ansible_user: ubuntu
          ansible_ssh_private_key_file: ~/.ssh/id_rsa
```

Then deploy normally:
```sh
./ansible-deploy.sh --node all --network-dir local-devnet
```

**Note:** For remote deployment, ensure:
- SSH key-based authentication is configured
- Docker is installed on remote hosts (or use `--deployment-mode binary`)
- Required ports are open (QUIC ports, metrics ports)
- Genesis files are accessible (copied or mounted)

### Using Ansible Directly

You can also run Ansible playbooks directly:

```sh
cd ansible

# Run main playbook
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  -e "network_dir=$(pwd)/../local-devnet" \
  -e "node_names=all" \
  -e "generate_genesis=true"

# Run only genesis generation
ansible-playbook -i inventory/hosts.yml playbooks/genesis.yml \
  -e "network_dir=$(pwd)/../local-devnet"

# Run with specific tags
ansible-playbook -i inventory/hosts.yml playbooks/deploy-nodes.yml \
  -e "network_dir=$(pwd)/../local-devnet" \
  -e "node_names=zeam_0" \
  --tags zeam
```

### Ansible Variables

Key variables can be set via command-line or in `inventory/group_vars/all.yml`:

- `network_dir`: Network directory path (required)
- `genesis_dir`: Genesis directory path (derived from network_dir)
- `data_dir`: Data directory path (derived from network_dir)
- `node_names`: Nodes to deploy (default: 'all')
- `generate_genesis`: Generate genesis files (default: true)
- `clean_data`: Clean data directories (default: false)
- `deployment_mode`: docker or binary (default: docker)
- `validator_config`: Validator config path (default: 'genesis_bootnode')

### Comparing Shell Scripts vs Ansible

Both deployment methods are available:

| Feature | Shell Scripts (`spin-node.sh`) | Ansible (`ansible-deploy.sh`) |
|---------|-------------------------------|-------------------------------|
| **Use Case** | Local development, quick setup | Production, remote deployment |
| **Complexity** | Simple, direct | More structured |
| **Remote Deployment** | No | Yes |
| **Idempotency** | No | Yes |
| **State Management** | Manual | Declarative |
| **Multi-Host** | No | Yes |
| **Rollback** | Manual | Built-in capabilities |

**Recommendation:** 
- Use `spin-node.sh` for local development and quick testing
- Use `ansible-deploy.sh` for production deployments and remote hosts

## Deployment Modes

Ansible supports three deployment modes:

| Mode | Use Case | Command |
|------|----------|---------|
| **Docker** | Local development, simple testing | `--deployment-mode docker` (default) |
| **Binary** | Remote servers without Docker | `--deployment-mode binary` |
| **Kubernetes** | Production-like, multi-host, orchestration | `--deployment-mode kubernetes` |

## Kubernetes Deployment

Deploy Lean nodes to a Kubernetes cluster for production-like testing and multi-host deployments.

### Prerequisites

#### 1. Install kubectl

```bash
# macOS (ARM/Apple Silicon)
arch -arm64 brew install kubectl

# macOS (Intel)
brew install kubectl

# Ubuntu/Debian
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Verify installation
kubectl version --client
```

#### 2. Set Up Local Kubernetes Cluster

Choose one option:

**Minikube (Recommended):**
```bash
# Install (macOS ARM/Apple Silicon)
arch -arm64 brew install minikube

# Install (macOS Intel)
brew install minikube

# Start
minikube start
```

**Docker Desktop:**
```bash
# Docker Desktop → Settings → Kubernetes → Enable Kubernetes
```

**kind:**
```bash
# Install (macOS ARM/Apple Silicon)
arch -arm64 brew install kind

# Install (macOS Intel)
brew install kind

# Create cluster
kind create cluster --name lean-test
```

#### 3. Configure Access

```bash
# Verify cluster is running
kubectl cluster-info
```

#### 4. Install Ansible Collections

```bash
cd ansible
ansible-galaxy install -r requirements.yml
```

### Deployment

#### Quick Deploy

```bash
# Deploy all nodes
./ansible-deploy.sh --node all --network-dir local-devnet \
  --deployment-mode kubernetes --generate-genesis

# Deploy specific nodes
./ansible-deploy.sh --node zeam_0,ream_0 --network-dir local-devnet \
  --deployment-mode kubernetes
```

#### Automated Testing

Run the automated test script:
```bash
# Basic test
./ansible/test-k8s-deployment.sh

# Test with cleanup
./ansible/test-k8s-deployment.sh cleanup
```

### Verification & Management

#### Check Status

```bash
# List all resources
kubectl get all -n lean-network

# View pods
kubectl get pods -n lean-network

# View services
kubectl get svc -n lean-network
```

#### Access Logs

```bash
# Follow logs
kubectl logs -n lean-network zeam_0 -f

# Recent logs only
kubectl logs -n lean-network zeam_0 --tail=50
```

#### Access Metrics

```bash
# Port forward metrics service
kubectl port-forward -n lean-network svc/zeam_0-metrics 8080:8080

# Access metrics (in another terminal)
curl http://localhost:8080/metrics
```

#### Troubleshooting

```bash
# Pod not starting?
kubectl describe pod -n lean-network <pod-name>

# Check events
kubectl get events -n lean-network --sort-by=.metadata.creationTimestamp

# PVC issues?
kubectl get pvc -n lean-network
kubectl describe pvc -n lean-network <pvc-name>

# Check storage classes
kubectl get storageclass
```

#### Cleanup

```bash
# Delete namespace (removes everything)
kubectl delete namespace lean-network

# Delete specific deployment
kubectl delete deployment zeam_0 -n lean-network
```

### Configuration

Edit `ansible/inventory/group_vars/all.yml` to customize:

```yaml
k8s_namespace: lean-network       # Change namespace
k8s_storage_size: 20Gi            # Increase storage
k8s_memory_limit: 4Gi             # More memory
k8s_storage_class: standard       # Your storage class
```

### Comparison: Docker vs Kubernetes

| Task | Docker | Kubernetes |
|------|--------|------------|
| Deploy | `--deployment-mode docker` | `--deployment-mode kubernetes` |
| Status | `docker ps` | `kubectl get pods -n lean-network` |
| Logs | `docker logs <name>` | `kubectl logs -n lean-network <name>` |
| Access | `curl localhost:PORT` | `kubectl port-forward svc/<svc> PORT` |
| Clean | `docker rm -f <name>` | `kubectl delete namespace lean-network` |

📖 **Detailed Kubernetes documentation:** [ansible/KUBERNETES.md](ansible/KUBERNETES.md)

## Client branches

Clients can maintain their own branches to integrated and use binay with their repos as the static targets (check `git diff main zeam_repo`). And those branches can be rebased as per client convinience whenever the `main` code is updated.
