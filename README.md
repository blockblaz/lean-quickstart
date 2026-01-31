# lean quickstart

A single command line quickstart to spin up lean node(s)

### Benefits

- ✅ **Single source of truth** - `validator-config.yaml`
    - defines everything
    - Generates full genesis state (JSON + SSZ) plus config files
    - add/remove nodes, modify validator count, assign IPs, ports, enr keys
    - Uses PK's `eth-beacon-genesis` docker tool (not custom tooling)
    - Generates PQ keys based on specified configuration in `validator-config.yaml`
        - Force regen with flag `--forceKeyGen` when supplied with `generateGenesis`
- ✅ Integrates zeam, ream, qlean, lantern, lighthouse, grandine, ethlambda
- ✅ Configure to run clients in docker or binary mode for easy development
- ✅ Linux & Mac compatible & tested
- ✅ Option to operate on single or multiple nodes or `all`

### Requirements

1. Shell terminal: Preferably linux especially if you want to pop out separate new terminals for node
2. **Docker**: Required to run PK's eth-beacon-genesis tool and hash-sig-cli for post-quantum keys
   - Install from: [Docker Desktop](https://docs.docker.com/get-docker/)
3. **yq**: YAML processor for automated configuration parsing
   - Install on macOS: `brew install yq`
   - Install on Linux: See [yq installation guide](https://github.com/mikefarah/yq#install)

## Quick Start

### First Time Setup:
```sh
# 1. Clone the repository
git clone <repo-url>
cd lean-quickstart
```

## Scenarios

### Quickly startup various nodes as a local devnet

**Using spin-node.sh (single entry point for all operations):**
```sh
# Local deployment (default)
NETWORK_DIR=local-devnet ./spin-node.sh --node all --generateGenesis --popupTerminal

# Ansible deployment (set deployment_mode: ansible in validator-config.yaml or use --deploymentMode ansible)
NETWORK_DIR=local-devnet ./spin-node.sh --node all --generateGenesis --deploymentMode ansible

# Tools server setup (Docker + tool images on hosts in ansible/inventory/tools_servers.yml; no NETWORK_DIR or --node)
./spin-node.sh --setupToolsServer [--sshKey PATH] [--useRoot]

# Stop nodes (local or Ansible)
NETWORK_DIR=local-devnet ./spin-node.sh --node all --stop
```
> 📖 **Note**: When deployment mode is `ansible`, the script automatically uses `ansible-devnet/genesis/validator-config.yaml` and generates genesis files in `ansible-devnet/genesis/`. This keeps local and remote deployment configurations separate. See [Ansible Deployment](#ansible-deployment) section or [ansible/README.md](ansible/README.md) for details

### Startup specific nodes only

```sh
# Run only zeam_0 and ream_0 nodes (comma-separated)
NETWORK_DIR=local-devnet ./spin-node.sh --node zeam_0,ream_0 --generateGenesis --popupTerminal

# Run only zeam_0 and qlean_0 nodes (space-separated)
NETWORK_DIR=local-devnet ./spin-node.sh --node "zeam_0 qlean_0" --generateGenesis --popupTerminal

# Run only a single node
NETWORK_DIR=local-devnet ./spin-node.sh --node zeam_0 --generateGenesis --popupTerminal
```
> 💡 **Note**: The same `spin-node.sh` command works for both local and Ansible deployments. The deployment mode is determined by the `deployment_mode` field in `validator-config.yaml` or the `--deploymentMode` parameter. When using Ansible deployment mode, the script automatically uses `ansible-devnet/genesis/validator-config.yaml` to keep configurations separate.
  

### Enabling metrics

```sh
# Start all nodes with metrics enabled
NETWORK_DIR=local-devnet ./spin-node.sh --node all --generateGenesis --metrics
```

## Args

1. `NETWORK_DIR` is an env to specify the network directory. Should have a `genesis` directory with genesis config. A `data` folder will be created inside this `NETWORK_DIR` if not already there.
   - **For local deployments**: Use `local-devnet` (or any custom directory)
   - **For Ansible deployments**: When `deployment_mode: ansible` is set, the script automatically uses `ansible-devnet/` directory instead, keeping configurations separate
  `genesis` directory should have the following files

    a. `validator-config.yaml` which has node setup information for all the bootnodes
    b. `validators.yaml` which assigns validator indices
    c. `nodes.yaml` which has the enrs generated for each of the respective nodes.
    d. `config.yaml` the actual network config

2. `--generateGenesis` regenerate all genesis files with fresh genesis time and clean data directories
3. `--forceKeyGen` force regeneration of hash-sig validator keys even if they already exist. 
   - Must be used together with `--generateGenesis` flag
   - This will **overwrite** existing keys in `genesis/hash-sig-keys/`
   - Use this when you need to regenerate keys (e.g., after key exhaustion, configuration changes, or testing)
   - Example: `NETWORK_DIR=local-devnet ./spin-node.sh --node all --generateGenesis --forceKeyGen`
4. `--popupTerminal` if you want to pop out new terminals to run the nodes, opens gnome terminals
5. `--node` specify which node(s) you want to run:
   - Use `all` to run all the nodes in a single go
   - Specify a single node name (e.g., `zeam_0`) to run just that node
   - Use comma-separated node names (e.g., `zeam_0,qlean_0`) to run multiple specific nodes
   - Use whitespace-separated node names (e.g., `"zeam_0 ream_0"`) to run multiple specific nodes
   
   The client is provided this input so as to parse the correct node configuration to startup the node.
6. `--validatorConfig` is the path to specify your nodes `validator-config.yaml`, `validators.yaml` (for which `--node` is still the node key to index) if your node is not a bootnode.
   If unspecified it assumes value of `genesis_bootnode` which is to say that your node config is to be picked from `genesis` folder with `--node` as the node key index.
   This value is further provided to the client so that they can parse the correct config information.
7. `--deploymentMode` specifies the deployment mode: `local` or `ansible`. 
   - If provided, this overrides the `deployment_mode` field in `validator-config.yaml`
   - If not provided, the value from `validator-config.yaml` is used (defaults to `local` if not specified)
   - **When set to `ansible`**: The script automatically uses `ansible-devnet/genesis/validator-config.yaml` and generates genesis files in `ansible-devnet/genesis/` (unless `--validatorConfig` is explicitly provided)
   - Examples: `--deploymentMode local` or `--deploymentMode ansible`
8. `--sshKey` or `--private-key` specifies the SSH private key file to use for remote Ansible deployments.
   - Only used when `deployment_mode: ansible` is set
   - Path to SSH private key file (e.g., `~/.ssh/id_rsa` or `/path/to/custom_key`)
   - If not provided, Ansible will use the default SSH key (`~/.ssh/id_rsa`) or keys configured in `ansible.cfg`
   - Example: `--sshKey ~/.ssh/custom_key` or `--private-key /path/to/key.pem`
9. `--useRoot` flag specifies to use `root` user for remote Ansible deployments.
   - Only used when `deployment_mode: ansible` is set
   - If not specified, uses the current user (whoami) for SSH connections
   - If specified, uses `root` user for SSH connections
   - Example: `--useRoot` to connect as root user
10. `--tag` specifies the Docker image tag to use for zeam, ream, qlean, lantern, lighthouse, grandine and ethlambda containers.
   - If provided, all clients will use this tag (e.g., `blockblaz/zeam:${tag}`, `ghcr.io/reamlabs/ream:${tag}`, `qdrvm/qlean-mini:${tag}`, `piertwo/lantern:${tag}`, `hopinheimer/lighthouse:${tag}`, `sifrai/grandine:${tag}`, `ghcr.io/lambdaclass/ethlambda:${tag}`)
   - If not provided, defaults to `latest` for zeam, ream, and lantern, and `dd67521` for qlean
   - The script will automatically pull the specified Docker images before running containers
   - Example: `--tag devnet0` or `--tag devnet1`
11. `--metrics` enables metrics collection on all nodes. When specified, each client will activate its metrics endpoint according to its implementation. Metrics ports are configured per node in `validator-config.yaml`.
12. `--setupToolsServer` runs the tools server setup playbook: ensures Docker is installed on hosts defined in `ansible/inventory/tools_servers.yml`, then pulls tool images (e.g. `blockblaz/leanpoint:latest`). Does not require `NETWORK_DIR` or `--node`. Edit `ansible/inventory/tools_servers.yml` to add your tools server host(s). Example: `./spin-node.sh --setupToolsServer --sshKey ~/.ssh/key --useRoot`
13. `--stop` stops the specified node(s) (local containers or remote via Ansible). Example: `NETWORK_DIR=local-devnet ./spin-node.sh --node all --stop`

### Clients supported

Current following clients are supported:

1. Zeam
2. Ream
3. Qlean
4. Lantern
5. Lighthouse
6. Grandine

However adding a lean client to this setup is very easy. Feel free to do the PR or reach out to the maintainers.

## How It Works

The quickstart includes an automated genesis generator that eliminates the need for hardcoded files and uses `validator-config.yaml` as the source of truth. 

**Configuration File Location:**
- **Local deployments**: The `validator-config.yaml` file is contained in the `genesis` folder of the provided `NETWORK_DIR` folder (e.g., `local-devnet/genesis/validator-config.yaml`)
- **Ansible deployments**: When `deployment_mode: ansible` is set (either in the config file or via `--deploymentMode ansible`), the script automatically uses `ansible-devnet/genesis/validator-config.yaml` instead. This keeps local and remote deployment configurations separate.

Then post genesis generation, the quickstart spins the nodes as per their respective client cmds.

### Directory Structure

The quickstart uses separate directories for local and Ansible deployments:

```
lean-quickstart/
├── local-devnet/              # Local development
│   ├── genesis/
│   │   └── validator-config.yaml  # Local IPs (127.0.0.1)
│   └── data/                      # Node data directories
│
└── ansible-devnet/            # Ansible/remote deployment
    ├── genesis/
    │   └── validator-config.yaml  # Remote IPs (your server IPs)
    └── data/                      # Node data directories
```

**Automatic Directory Selection:**
- When `deployment_mode: ansible` is set (in config or via `--deploymentMode ansible`), the script automatically uses `ansible-devnet/genesis/validator-config.yaml`
- This keeps local and remote configurations completely separate
- Genesis files are generated in the appropriate directory based on deployment mode

### Configuration

The `validator-config.yaml` file defines the shuffle algorithm, active epoch configuration, and validator nodes specifications:

```yaml
shuffle: roundrobin
config:
  activeEpoch: 18              # Required: Exponent for active epochs (2^18 = 262,144 signatures)
  keyType: "hash-sig"          # Required: Network-wide signature scheme (hash-sig for post-quantum security)
validators:                    # validator nodes specification 
  - name: "zeam_0"             # a 0rth zeam node
    privkey: "bdf953adc161873ba026330c56450453f582e3c4ee6cb713644794bcfdd85fe5"
    enrFields:
      ip: "127.0.0.1"
      quic: 9000
    metricsPort: 8080
    count: 1                   # validator keys to be assigned to this node
```

**Required Top-Level Fields:**
- `shuffle`: Validator assignment (to nodes) shuffle algorithm (e.g., `roundrobin`)
- `config.activeEpoch`: Exponent for active epochs used in hash-sig key generation (2^activeEpoch signatures per active period)
- `config.keyType`: Network-wide signature scheme - must be `"hash-sig"` for post-quantum security

### Step 1 - Genesis Generation

The `spin-node.sh` triggers genesis generator (`generate-genesis.sh`) which generates the following files based on `validator-config.yaml`:

1. **post-quantum secure validator keypairs** in `genesis/hash-sig-keys` unless already generated or forced with `--forceKeyGen`
2. **config.yaml** - With the updated genesis time in short future and pubkeys of the generated keypairs
3. **validators.yaml** - Validator index assignments using round-robin distribution
4. **nodes.yaml** - ENR (Ethereum Node Records) for peer discovery
5. **genesis.json** - Genesis state in JSON format
6. **genesis.ssz** - Genesis state in SSZ format


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

#### Hash-Based Signature (Post-Quantum) Scheme Validator Keys

**Tool's Docker Image**: `HASH_SIG_CLI_IMAGE="blockblaz/hash-sig-cli:latest"`
**Source**: https://github.com/blockblaz/hash-sig-cli

Using the above docker tool the following files are generated (unless already generated or forced via `--forceKeyGen` flag):

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

**Signature Scheme:**
The system uses the **SIGTopLevelTargetSumLifetime32Dim64Base8** hash-based signature scheme, which provides:

- **Post-quantum security**: Resistant to attacks from quantum computers
- **Active epochs**: as per `config.activeEpoch` for e.g. 2^18 (262,144 signatures)
- **Total lifetime**: 2^32 (4,294,967,296 signatures)
- **Stateful signatures**: Uses hierarchical signature tree structure


**Validator Fields:**
Hash-sig key files are automatically indexed based on the validator index (first validator uses `validator_0_*.json`, second uses `validator_1_*.json`, etc.)

#### Genesis config files

**Tool's Docker Image**: `PK_DOCKER_IMAGE="ethpandaops/eth-beacon-genesis:pk910-leanchain"`
**Source**: https://github.com/ethpandaops/eth-beacon-genesis/pull/36

`config.yaml` is generated with the appropriate genesis time (in short future) along with the list pubkeys of the validators in the correct sequence. For e.g:

```yaml
# Genesis Settings
GENESIS_TIME: 1763712794
# Key Settings
ACTIVE_EPOCH: 10
# Validator Settings  
VALIDATOR_COUNT: 2
GENESIS_VALIDATORS:
  - "4b3c31094bcc9b45446b2028eae5ad192b2df16778837b10230af102255c9c5f72d7ba43eae30b2c6a779f47367ebf5a42f6c959"
  - "8df32a54d2fbdf3a88035b2fe3931320cb900d364d6e7c56b19c0f3c6006ce5b3ebe802a65fe1b420183f62e830a953cb33b7804"
```

This `config.yaml` is consumed by the clients to directly generate the genesis `in-client`. Note that clients are supposed to ignore `genesis.ssz` and `genesis.json` as their formats have not been updated.

`validators.yaml` is generated for validator index assignments to the nodes:

```yaml
zeam_0:
    - 0
    - 3
ream_0:
    - 1
    - 4
qlean_0:
    - 2
```

**Recommended:** `annotated_validators.yaml` is also generated and should be preferred by client software as it includes public keys and private key file references directly, eliminating the need for clients to derive key filenames from validator indices:

```yaml
zeam_0:
  - index: 0
    pubkey_hex: 4b3c31094bcc9b45446b2028eae5ad192b2df16778837b10230af102255c9c5f72d7ba43eae30b2c6a779f47367ebf5a42f6c959
    privkey_file: validator_0_sk.json
  - index: 3
    pubkey_hex: 8df32a54d2fbdf3a88035b2fe3931320cb900d364d6e7c56b19c0f3c6006ce5b3ebe802a65fe1b420183f62e830a953cb33b7804
    privkey_file: validator_3_sk.json

ream_0:
  - index: 1
    pubkey_hex: 5b15f72f90bd655b039f9839c36951454b89c605f8c334581cfa832bdd0c994a1350094f7e22617d77607b067b0aa2439e0ead7d
    privkey_file: validator_1_sk.json
  - index: 4
    pubkey_hex: 71bf8f73980591574de34a0db471da74f5cfd84d4731d53f47bf3023b26c2638ac5bd24993ea71492fedbd6c4afe5c299213b76b
    privkey_file: validator_4_sk.json

qlean_0:
  - index: 2
    pubkey_hex: b87e69568a347d1aa811cc158634fb1f4e247c5509ad2b1652a8d758ec0ab0796954e307b97dd6284fbb30088c2e595546fdf663
    privkey_file: validator_2_sk.json
```

`nodes.yaml` provide enrs of all the nodes so that clients don't have to run a discovery protocol:

```yaml
- enr:-IW4QMn2QUYENcnsEpITZLph3YZee8Y3B92INUje_riQUOFQQ5Zm5kASi7E_IuQoGCWgcmCYrH920Q52kH7tQcWcPhEBgmlkgnY0gmlwhH8AAAGEcXVpY4IjKIlzZWNwMjU2azGhAhMMnGF1rmIPQ9tWgqfkNmvsG-aIyc9EJU5JFo3Tegys
- enr:-IW4QDc1Hkslu0Bw11YH4APkXvSWukp5_3VdIrtwhWomvTVVAS-EQNB-rYesXDxhHA613gG9OGR_AiIyE0VeMltTd2cBgmlkgnY0gmlwhH8AAAGEcXVpY4IjKYlzZWNwMjU2azGhA5_HplOwUZ8wpF4O3g4CBsjRMI6kQYT7ph5LkeKzLgTS
```

### Step 2 - Spinning Nodes

Post genesis generation, the quickstarts loads and calls the appropriate node's client cmd from `client-cmds` folder where either `docker` or `binary` cmd is picked as per the `node_setup` mode. (Generally `binary` mode is handy for local interop debugging for a client).

**Client Integration:**
Your client implementation should read these environment variables and use the hash-sig keys for validator operations.

 - `$item` - the node name for which this cmd is being executed, index into `validator-config.yaml` for its configuration
 - `$configDir` - the abs folder housing `genesis` configuration (same as `NETWORK_DIR` env variable provided while executing shell command), already mapped to `/config` in the docker mode
 - A generic data folder is created inside config folder accessible as `$dataDir` with `$dataDir/$item` to be used as the data dir for a particular node to be used for binary format, already mapped to `/data` in the docker mode
 - Variables read and available from `validator-config.yaml` (use them or directly read configuration from the `validator-config.yaml` using `$item` as the index into `validators` section)
   - `$metricsPort`
   - `$quicPort` 
   - `$item.key` filename of the p2p `privkey` read and dumped into file from `validator-config.yaml` inside config dir (so `$configDir/$item.key` or `/config/$item.key`)

Here is an example client cmd:
```bash
#!/bin/bash

#-----------------------qlean setup----------------------
# expects "qlean" submodule or symlink inside "lean-quickstart" root directory
# https://github.com/qdrvm/qlean-mini
node_binary="$scriptDir/qlean/build/src/executable/qlean \
      --modules-dir $scriptDir/qlean/build/src/modules \
      --genesis $configDir/config.yaml \
      --validator-registry-path $configDir/validators.yaml \
      --bootnodes $configDir/nodes.yaml \
      --data-dir $dataDir/$item \
      --node-id $item --node-key $configDir/$privKeyPath \
      --listen-addr /ip4/0.0.0.0/udp/$quicPort/quic-v1 \
      --metrics-port $metricsPort"

node_docker="--platform linux/amd64 qdrvm/qlean-mini:dd67521 \
      --genesis /config/config.yaml \
      --validator-registry-path /config/validators.yaml \
      --bootnodes /config/nodes.yaml \
      --data-dir /data \
      --node-id $item --node-key /config/$privKeyPath \
      --listen-addr /ip4/0.0.0.0/udp/$quicPort/quic-v1 \
      --metrics-port $metricsPort"

# choose either binary or docker
node_setup="docker"
```

## Key Management

### Key Lifetime

Each hash-sig key has a **finite lifetime** of 2^32 signatures. The keys are structured as:
- **Active epochs**: 2^18 epochs before requiring key rotation
- **Total lifetime**: 2^32 total signatures possible

### Key Rotation

Hash-based signatures are **stateful** - each signature uses a unique one-time key from the tree. Once exhausted, keys must be rotated.

**Regenerating Keys:**

You can regenerate hash-sig keys using either method:

1. **Using `spin-node.sh` with `--forceKeyGen` flag** (recommended):
```sh
# Regenerate all hash-sig keys and genesis files
NETWORK_DIR=local-devnet ./spin-node.sh --node all --generateGenesis --forceKeyGen
```

2. **Using `generate-genesis.sh` directly**:
```sh
# Regenerate all hash-sig keys
./generate-genesis.sh local-devnet/genesis --forceKeyGen
```

**Note**: The `--forceKeyGen` flag is required to overwrite existing keys. Without it, the generator will skip key generation if keys already exist.

**Warning**: 
- ⚠️ Regenerating keys will **overwrite** existing keys in `genesis/hash-sig-keys/`
- ⚠️ Keep track of signature counts to avoid key exhaustion
- ⚠️ Ensure you have backups of important keys before regenerating

### Key Security

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
# Hash-Signature Validator Keys Manifest
# Generated by hash-sig-cli

key_scheme: SIGTopLevelTargetSumLifetime32Dim64Base8
hash_function: Poseidon2
encoding: TargetSum
lifetime: 4294967296
log_num_active_epochs: 10
num_active_epochs: 1024
num_validators: 2

validators:
  - index: 0
    pubkey_hex: 0x4b3c31094bcc9b45446b2028eae5ad192b2df16778837b10230af102255c9c5f72d7ba43eae30b2c6a779f47367ebf5a42f6c959
    privkey_file: validator_0_sk.json

  - index: 1
    pubkey_hex: 0x8df32a54d2fbdf3a88035b2fe3931320cb900d364d6e7c56b19c0f3c6006ce5b3ebe802a65fe1b420183f62e830a953cb33b7804
    privkey_file: validator_1_sk.json

```

## Troubleshooting

**Problem**: Hash-sig keys not loading during node startup
```
Warning: Hash-sig public key not found at genesis/hash-sig-keys/validator_0_pk.json
```

**Solution**: Run the genesis generator to create keys:
```sh
# Using spin-node.sh (recommended)
NETWORK_DIR=local-devnet ./spin-node.sh --node all --generateGenesis

# Or using generate-genesis.sh directly
./generate-genesis.sh local-devnet/genesis
```

---

**Problem**: Hash-sig key file not found
```
Warning: Hash-sig secret key not found at genesis/hash-sig-keys/validator_5_sk.json
```

**Solution**: This usually means you have more validators configured than hash-sig keys generated. Regenerate genesis files:
```sh
# Using spin-node.sh (recommended)
NETWORK_DIR=local-devnet ./spin-node.sh --node all --generateGenesis

# Or using generate-genesis.sh directly
./generate-genesis.sh local-devnet/genesis
```

**Problem**: Need to regenerate keys (e.g., after key exhaustion or configuration changes)

**Solution**: Use the `--forceKeyGen` flag to force regeneration:
```sh
# Regenerate keys and all genesis files
NETWORK_DIR=local-devnet ./spin-node.sh --node all --generateGenesis --forceKeyGen

# Or using generate-genesis.sh directly
./generate-genesis.sh local-devnet/genesis --forceKeyGen
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

### Using Ansible Deployment

**Recommended: Use `spin-node.sh` (Unified Entry Point)**

`spin-node.sh` is the primary entry point for all deployments, including Ansible. Simply set `deployment_mode: ansible` in your `validator-config.yaml`:

```sh
# Set deployment_mode: ansible in validator-config.yaml, then:
NETWORK_DIR=local-devnet ./spin-node.sh --node all --generateGenesis
```

This automatically calls `run-ansible.sh` internally, which reads the default deployment mode from `ansible/inventory/group_vars/all.yml`.

**Advanced: Direct Ansible Control with `ansible-deploy.sh`**

For advanced Ansible workflows requiring direct control (e.g., `--playbook`, `--tags`, `--check`, `--diff`), you can use `ansible-deploy.sh` directly:

```sh
# First generate genesis files locally
./generate-genesis.sh local-devnet/genesis

# Then deploy nodes (genesis files are copied to remote hosts automatically)
./ansible-deploy.sh --node zeam_0,ream_0 --network-dir local-devnet
```

However, for most use cases, `spin-node.sh` is recommended as it provides a consistent interface for both local and Ansible deployments.

### Ansible Benefits

- ✅ **Remote Deployment**: Deploy nodes to remote servers
- ✅ **Idempotency**: Safe to run multiple times
- ✅ **Infrastructure as Code**: Version-controlled deployment configuration
- ✅ **Multi-Host Support**: Deploy to multiple hosts in parallel
- ✅ **Better State Management**: Track and manage node lifecycle
- ✅ **Extensible**: Easy to add new roles and playbooks

### Installing Ansible

**Minimum Required Version:** Ansible 2.13+

The Ansible configuration uses `result_format = yaml` which requires Ansible 2.13 or later (released May 2022).

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

**Verify your version meets the requirement:**
```sh
ansible --version  # Must be 2.13+
```

### Installing Ansible Dependencies

Install required Ansible collections:

```sh
cd ansible
ansible-galaxy install -r requirements.yml
```

### Quick Start with Ansible

**Recommended: Using `spin-node.sh` (set `deployment_mode: ansible` in validator-config.yaml):**

```sh
# Deploy all nodes with genesis generation
NETWORK_DIR=local-devnet ./spin-node.sh --node all --generateGenesis

# Deploy specific nodes
NETWORK_DIR=local-devnet ./spin-node.sh --node zeam_0,ream_0 --generateGenesis

# Deploy with clean data directories
NETWORK_DIR=local-devnet ./spin-node.sh --node all --generateGenesis --cleanData
```

**Alternative: Using `ansible-deploy.sh` directly (for advanced Ansible options):**

```sh
# First generate genesis files locally
./generate-genesis.sh local-devnet/genesis

# Deploy specific nodes (genesis files are copied to remote hosts automatically)
./ansible-deploy.sh --node zeam_0,ream_0 --network-dir local-devnet

# Copy genesis files to remote hosts only
./ansible-deploy.sh --playbook copy-genesis.yml --network-dir local-devnet

# Dry run (check mode)
./ansible-deploy.sh --node zeam_0,ream_0 --network-dir local-devnet --check
```

### Ansible Command-Line Options (Advanced)

The following options are available when using `ansible-deploy.sh` directly for advanced Ansible workflows. For most use cases, use `spin-node.sh` instead (see [Quick Start with Ansible](#quick-start-with-ansible) above).

The `ansible-deploy.sh` wrapper script provides the following options:

| Option | Description | Example |
|--------|-------------|---------|
| `--node NODES` | Nodes to deploy (single or comma/space-separated) | `--node zeam_0,ream_0` |
| `--network-dir DIR` | Network directory | `--network-dir local-devnet` |
| `--clean-data` | Clean data directories before deployment | `--clean-data` |
| `--validator-config PATH` | Path to validator-config.yaml | `--validator-config custom/path.yaml` |
| `--deployment-mode MODE` | Deployment mode: docker or binary | `--deployment-mode binary` |
| `--playbook PLAYBOOK` | Ansible playbook to run | `--playbook copy-genesis.yml` |
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
│   ├── site.yml             # Main playbook (clean + copy genesis + deploy)
│   ├── clean-node-data.yml  # Clean node data directories
│   ├── generate-genesis.yml # Generate genesis files
│   ├── copy-genesis.yml     # Copy genesis files to remote hosts
│   ├── deploy-nodes.yml     # Node deployment playbook
│   ├── stop-nodes.yml       # Stop and remove nodes
│   └── helpers/             # Helper task files
│       └── deploy-single-node.yml # Single node deployment tasks
└── roles/
    ├── common/              # Common setup (Docker, yq, directories)
    ├── genesis/             # Genesis file generation
    ├── zeam/                # Zeam node role
    ├── ream/                # Ream node role
    ├── qlean/               # Qlean node role
    ├── lantern/             # Lantern node role
    ├── lighthouse/          # Lighthouse node role
    ├── grandine/            # Grandine node role
    └── ethlambda/           # EthLambda node role    
```

### Remote Deployment

The Ansible inventory is **automatically generated** from `validator-config.yaml`. 

**Configuration Setup:**

For Ansible deployments, create or update `ansible-devnet/genesis/validator-config.yaml` with your remote server IP addresses:

```yaml
deployment_mode: ansible
config:
  activeEpoch: 18
  keyType: "hash-sig"
validators:
  - name: "zeam_0"
    privkey: "..."
    enrFields:
      ip: "192.168.1.10"  # Remote IP address
      quic: 9000
    metricsPort: 8081
    count: 1
  - name: "ream_0"
    privkey: "..."
    enrFields:
      ip: "192.168.1.11"  # Remote IP address
      quic: 9001
    metricsPort: 8082
    count: 1
```

**Deployment:**

Then use `spin-node.sh` with `--deploymentMode ansible` (or set `deployment_mode: ansible` in the config file):

```sh
# If using default SSH key (~/.ssh/id_rsa)
NETWORK_DIR=local-devnet ./spin-node.sh --node all --generateGenesis --deploymentMode ansible

# If using a custom SSH key and root user
NETWORK_DIR=local-devnet ./spin-node.sh --node all --generateGenesis --deploymentMode ansible --sshKey ~/.ssh/custom_key --useRoot
```

> 💡 **Note**: When `deployment_mode: ansible` is set, the script automatically uses `ansible-devnet/genesis/validator-config.yaml` and generates all genesis files in `ansible-devnet/genesis/`. This keeps your local development (`local-devnet/`) and remote deployment (`ansible-devnet/`) configurations completely separate.

The inventory generator will automatically:
- Detect remote IPs (non-localhost) and configure remote connections
- Group nodes by client type (zeam_nodes, ream_nodes, qlean_nodes, lantern_nodes, lighthouse_nodes, grandine_nodes, ethlambda_nodes)
- Set appropriate connection parameters
- Apply SSH key file if provided via `--sshKey` parameter

**Note:** For remote deployment, ensure:
- SSH key-based authentication is configured
  - Use `--sshKey` parameter to specify custom SSH key: `--sshKey ~/.ssh/custom_key`
  - Use `--useRoot` flag to connect as root user (defaults to current user)
  - Or manually add `ansible_user` and `ansible_ssh_private_key_file` to the generated inventory
  - Or configure in `ansible/ansible.cfg` (see `private_key_file` option)
- Docker is installed on remote hosts (or use `deployment_mode: binary` in group_vars)
- Required ports are open (QUIC ports, metrics ports)
- Genesis files are accessible (copied or mounted)

### Using Ansible Directly

You can also run Ansible playbooks directly (after setting `deployment_mode: ansible` and running `spin-node.sh` once to generate the inventory):

```sh
cd ansible

# Run main playbook
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  -e "network_dir=$(pwd)/../local-devnet" \
  -e "node_names=zeam_0,ream_0"

# Copy genesis files to remote hosts only
ansible-playbook -i inventory/hosts.yml playbooks/copy-genesis.yml \
  -e "network_dir=$(pwd)/../local-devnet"

# Run with specific tags
ansible-playbook -i inventory/hosts.yml playbooks/deploy-nodes.yml \
  -e "network_dir=$(pwd)/../local-devnet" \
  -e "node_names=zeam_0" \
  --tags zeam
```

### Ansible Variables

Key variables can be set via command-line or in `ansible/inventory/group_vars/all.yml`:

- `network_dir`: Network directory path (required)
- `genesis_dir`: Genesis directory path (derived from network_dir)
- `data_dir`: Data directory path (derived from network_dir)
- `node_names`: Nodes to deploy (required, comma or space separated)
- `clean_data`: Clean data directories (default: false)
- `deployment_mode`: docker or binary (default: docker, defined in `ansible/inventory/group_vars/all.yml`)
- `validator_config`: Validator config path (default: 'genesis_bootnode')

**Note:** The default `deployment_mode` value is read from `ansible/inventory/group_vars/all.yml`. When using `spin-node.sh` with `deployment_mode: ansible`, it internally calls `run-ansible.sh` which reads this default value. You can override it by setting `deployment_mode` in your `validator-config.yaml` or via command-line arguments.

### Comparing Local vs Ansible Deployment

Both deployment modes use the same `spin-node.sh` entry point, controlled by `deployment_mode` in `validator-config.yaml`:

| Feature | Local (`deployment_mode: local`) | Ansible (`deployment_mode: ansible`) |
|---------|----------------------------------|--------------------------------------|
| **Use Case** | Local development, quick setup | Production, remote deployment |
| **Complexity** | Simple, direct | More structured |
| **Remote Deployment** | No | Yes |
| **Idempotency** | No | Yes |
| **State Management** | Manual | Declarative |
| **Multi-Host** | No | Yes |
| **Rollback** | Manual | Built-in capabilities |
| **Entry Point** | `spin-node.sh` | `spin-node.sh` (same command) |
| **Inventory** | N/A | Auto-generated from validator-config.yaml |

**Recommendation:** 
- Use `deployment_mode: local` for local development and quick testing
- Use `deployment_mode: ansible` for production deployments and remote hosts
- Both modes use the same `spin-node.sh` command - just change the `deployment_mode` in `validator-config.yaml`

## Deployment Modes

The quickstart supports two deployment modes:

| Mode | Use Case | Command |
|------|----------|---------|
| **Local** | Local development, quick testing | `deployment_mode: local` (default) |
| **Ansible** | Production, remote deployment, infrastructure automation | `deployment_mode: ansible` |

### Local Deployment Mode

Local deployment uses shell scripts to directly run Docker containers or binaries on the local machine. This is the default mode and is ideal for:
- Quick local development
- Testing and experimentation
- Single-machine setups

### Ansible Deployment Mode

Ansible deployment provides infrastructure automation and supports two sub-modes:

| Sub-Mode | Use Case | Command |
|----------|----------|---------|
| **Docker** | Deploy containers directly on hosts | `--deployment-mode docker` (default for Ansible) |
| **Binary** | Deploy binaries as systemd services | `--deployment-mode binary` |

Ansible mode is ideal for:
- Production deployments
- Remote server management
- Multi-host deployments
- Infrastructure as Code workflows

## Client branches

Clients can maintain their own branches to integrated and use binay with their repos as the static targets (check `git diff main zeam_repo`, it has two nodes, both specified to run `zeam` for sim testing in zeam using the quickstart generated genesis).
And those branches can be rebased as per client convinience whenever the `main` code is updated.
