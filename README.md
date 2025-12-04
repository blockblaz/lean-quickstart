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
- ✅ Integrates zeam, ream, qlean (and more incoming...)
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

```sh
NETWORK_DIR=local-devnet ./spin-node.sh --node all --generateGenesis --popupTerminal
```

### Startup specific nodes only

```sh
# Run only zeam_0 and ream_0 nodes (comma-separated)
NETWORK_DIR=local-devnet ./spin-node.sh --node zeam_0,ream_0 --generateGenesis --popupTerminal

# Run only zeam_0 and qlean_0 nodes (space-separated)
NETWORK_DIR=local-devnet ./spin-node.sh --node "zeam_0 qlean_0" --generateGenesis --popupTerminal

# Run only a single node
NETWORK_DIR=local-devnet ./spin-node.sh --node zeam_0 --generateGenesis --popupTerminal
```

### Enabling metrics

```sh
# Start all nodes with metrics enabled
NETWORK_DIR=local-devnet ./spin-node.sh --node all --generateGenesis --metrics
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
6. `--metrics` enables metrics collection on all nodes. When specified, each client will activate its metrics endpoint according to its implementation. Metrics ports are configured per node in `validator-config.yaml`.

### Clients supported

Current following clients are supported:

1. Zeam
2. Ream
3. Qlean

However adding a lean client to this setup is very easy. Feel free to do the PR or reach out to the maintainers.

## How It Works

The quickstart includes an automated genesis generator that eliminates the need for hardcoded files and uses `validator-config.yaml` as the source of truth. This file is to be contained in the `genesis` folder of the provided `NETWORK_DIR` folder you want to run quickstart on. Then post genesis generation, the quickstart spins the nodes as per their respective client cmds.

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

`validators.yaml` is generated for validator index assignments to the nodes and is supposed to be read by the client software to pickup their assigned validator indexes:

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

Hash-based signatures are **stateful** - each signature uses a unique one-time key from the tree. Once exhausted, keys must be rotated:

```sh
# Regenerate all hash-sig keys
./generate-genesis.sh local-devnet/genesis
```

**Warning**: Keep track of signature counts to avoid key exhaustion.

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

## Client branches

Clients can maintain their own branches to integrated and use binay with their repos as the static targets (check `git diff main zeam_repo`, it has two nodes, both specified to run `zeam` for sim testing in zeam using the quickstart generated genesis).
And those branches can be rebased as per client convinience whenever the `main` code is updated.
