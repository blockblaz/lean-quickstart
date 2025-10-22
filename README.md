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
4. **Docker**: Required to run PK's eth-beacon-genesis tool
   - Install from: [Docker Desktop](https://docs.docker.com/get-docker/)
5. **yq**: YAML processor for automated configuration parsing
   - Install on macOS: `brew install yq`
   - Install on Linux: See [yq installation guide](https://github.com/mikefarah/yq#install)

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
3. `--generateGenesis` force regeneration of genesis files (`validators.yaml`, `nodes.yaml`, and `.key` files) from `validator-config.yaml`
4. `--popupTerminal` if you want to pop out new terminals to run the nodes, opens gnome terminals
5. `--node` specify which node you want to run, use `all` to run all the nodes in a single go, otherwise you may specify which node you want to run from `validator_config.yaml`.
  The client is provided this input so as to parse the correct node configuration to startup the node.
6. `--validatorConfig` is the path to specify your nodes `validator_config.yaml`, `validators.yaml` (for which `--node` is still the node key to index) if your node is not a bootnode.
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
1. **Generates hash-sig keys** for N validators (Step 1 of genesis generation)
2. **Stores keys** in `genesis/hash-sig-keys/` directory
3. **Creates manifest** with key metadata and scheme information
4. **Loads keys** automatically when nodes start via environment variables

### Key Files Generated

For each validator, two files are created:

```
genesis/hash-sig-keys/
├── validator_0_pk.json          # Public key (~240 bytes)
├── validator_0_sk.json          # Secret key (~106 MB for 2^18 epochs)
├── validator_1_pk.json
├── validator_1_sk.json
├── validator_2_pk.json
├── validator_2_sk.json
└── validator-keys-manifest.yaml # Metadata about all keys
```

**Note**: Secret keys are large (~106 MB each for 2^18 epochs) because they contain the entire Merkle tree structure for efficient signing.

### Dual-Key System

Each validator uses **two separate key systems**:

| Key Type | Purpose | Location |
|----------|---------|----------|
| **Hash-sig keys** | Block signing (post-quantum secure) | `genesis/hash-sig-keys/validator_N_*.json` |
| **Standard keys** | P2P networking (ENR) | `genesis/node_name.key` |

This separation allows post-quantum security for critical operations (signing) while maintaining compatibility with existing P2P protocols (networking).

### Configuring Validators for Hash-Sig

In `validator-config.yaml`, add these fields to each validator:

```yaml
validators:
  - name: "zeam_0"
    privkey: "bdf953..."              # For ENR/networking (kept for compatibility)
    keyType: "hash-sig"               # Enable hash-based signatures
    hashSigKeyIndex: 0                # Index into generated keys (0, 1, 2, ...)
    enrFields:
      ip: "127.0.0.1"
      quic: 9000
    metricsPort: 8080
    count: 1
```

**Required fields**:
- `keyType: "hash-sig"` - Tells the system to use hash-based signatures
- `hashSigKeyIndex: N` - Maps validator to generated key file (validator_N_*.json)

### Running with Hash-Sig Keys

#### **Option 1: Fresh Start (Recommended)**
```sh
# Generate everything fresh with hash-sig keys
NETWORK_DIR=local-devnet ./spin-node.sh --node all --generateGenesis
```

This will:
1. Generate hash-sig keys for all validators
2. Create genesis files
3. Start nodes with keys loaded

#### **Option 2: Standalone Genesis Generation**
```sh
# Generate only genesis files (including hash-sig keys)
./generate-genesis.sh local-devnet/genesis

# Then start nodes (uses existing keys)
NETWORK_DIR=local-devnet ./spin-node.sh --node all
```

#### **Option 3: Start Without Regenerating Keys**
```sh
# Use existing genesis and hash-sig keys (no regeneration)
NETWORK_DIR=local-devnet ./spin-node.sh --node all
```

### Key Loading Process

When nodes start, the system automatically:

1. **Detects** `keyType: "hash-sig"` in `validator-config.yaml`
2. **Extracts** `hashSigKeyIndex` for the validator
3. **Validates** key files exist at expected paths
4. **Exports** environment variables for the client:
   ```bash
   HASH_SIG_PUBLIC_KEY=/path/to/validator_N_pk.json
   HASH_SIG_SECRET_KEY=/path/to/validator_N_sk.json
   HASH_SIG_KEY_INDEX=N
   ```
5. **Starts** validator client with keys available

You'll see this output when nodes start:
```
🔐 Validator uses hash-based signatures (post-quantum secure)
Hash-Sig Key Index: 0
Hash-Sig Public Key: /path/to/validator_0_pk.json
Hash-Sig Secret Key: /path/to/validator_0_sk.json
```

### Configuring Number of Validators

To change the number of validators:

1. **Edit** `genesis/config.yaml`:
   ```yaml
   VALIDATOR_COUNT: 5  # Change this number
   ```

2. **Edit** `genesis/validator-config.yaml` - add/remove validator entries:
   ```yaml
   validators:
     - name: "validator_0"
       keyType: "hash-sig"
       hashSigKeyIndex: 0
       # ... other fields ...
     - name: "validator_1"
       keyType: "hash-sig"
       hashSigKeyIndex: 1
       # ... other fields ...
     # Add more as needed...
   ```

3. **Run** genesis generation:
   ```sh
   ./generate-genesis.sh local-devnet/genesis
   ```

The system will automatically generate the correct number of hash-sig key pairs.

### Hash-Sig Tool Integration

The hash-sig keys are generated using the `hash-sig-cli` tool, integrated as a git submodule:

```
tools/hash-sig-cli/          # Git submodule
└── target/release/hashsig   # CLI binary
```

**Submodule Setup** (if needed):
```sh
# Initialize submodule
git submodule add https://github.com/blockblaz/hash-sig-cli.git tools/hash-sig-cli
cd tools/hash-sig-cli
git submodule update --init --recursive
cargo build --release
```

The genesis generator automatically checks for the tool and builds it if needed.

### Troubleshooting

**Keys not found error:**
```
Error: Hash-sig public key not found at .../validator_0_pk.json
Run generate-genesis.sh to generate hash-sig keys first
```
**Solution**: Run `./generate-genesis.sh local-devnet/genesis`

**Genesis time expired:**
```
Genesis time is X but should be greater than Y
```
**Solution**: Regenerate genesis with fresh time:
```sh
NETWORK_DIR=local-devnet ./spin-node.sh --node all --generateGenesis
```

**Large file sizes:**
- Secret keys are ~106 MB each for 2^18 epochs
- This is normal - they contain the entire Merkle tree
- Ensure sufficient disk space (N × 106 MB for N validators)

### Technical Details

**Key Generation Command**:
```sh
# Called automatically by generate-genesis.sh
hashsig generate-for-genesis \
  --num-validators 3 \
  --log-num-active-epochs 18 \
  --output-dir genesis/hash-sig-keys
```

**Output Structure**:
- Public keys: JSON with root hash and parameters
- Secret keys: JSON with PRF seed and full Merkle tree
- Manifest: YAML with scheme info and key mappings

**Security Properties**:
- Post-quantum secure (resistant to quantum attacks)
- Stateful: Each (secret_key, epoch) pair must be used only once
- Forward secure: Compromise at epoch N doesn't affect epochs < N

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

Clients can maintain their own branches to integrated and use binay with their repos as the static targets (check `git diff main zeam_repo`). And those branches can be rebased as per client convinience whenever the `main` code is updated.
