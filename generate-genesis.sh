#!/bin/bash
# Genesis Generator for Lean Quickstart (Using PK's eth-beacon-genesis Tool)
# Uses PK's official docker image for leanchain genesis generation
# PR: https://github.com/ethpandaops/eth-beacon-genesis/pull/36

set -e

# ========================================
# Configuration
# ========================================
PK_DOCKER_IMAGE="ethpandaops/eth-beacon-genesis:pk910-leanchain"

# ========================================
# Usage and Help
# ========================================
show_usage() {
    cat << EOF
Usage: $0 <genesis-directory>

Generate genesis configuration files using PK's eth-beacon-genesis tool.
Generates: config.yaml, validators.yaml, nodes.yaml, genesis.json, genesis.ssz, and .key files

Arguments:
  genesis-directory    Path to the genesis directory containing:
                       - config.yaml (with GENESIS_TIME and VALIDATOR_COUNT)
                       - validator-config.yaml (with node configurations)

Example:
  $0 local-devnet/genesis

Generated Files:
  - config.yaml        Updated with correct VALIDATOR_COUNT
  - validators.yaml    Validator index assignments for each node
  - nodes.yaml         ENR (Ethereum Node Records) for peer discovery
  - genesis.json       Genesis state in JSON format
  - genesis.ssz        Genesis state in SSZ format
  - <node>.key         Private key files for each node

Requirements:
  - Docker (to run PK's eth-beacon-genesis tool)
  - yq: YAML processor (install: brew install yq)

Docker Image: ethpandaops/eth-beacon-genesis:pk910-leanchain
PR: https://github.com/ethpandaops/eth-beacon-genesis/pull/36

EOF
}

# Check for help flag
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    show_usage
    exit 0
fi

# ========================================
# Validate Arguments
# ========================================
if [ -z "$1" ]; then
    echo "❌ Error: Missing genesis directory argument"
    echo ""
    show_usage
    exit 1
fi

GENESIS_DIR="$1"
CONFIG_FILE="$GENESIS_DIR/config.yaml"
VALIDATOR_CONFIG_FILE="$GENESIS_DIR/validator-config.yaml"

# ========================================
# Check Dependencies
# ========================================
echo "🔍 Checking dependencies..."

# Check for yq
if ! command -v yq &> /dev/null; then
    echo "❌ Error: yq is required but not installed"
    echo "   Install on macOS: brew install yq"
    echo "   Install on Linux: https://github.com/mikefarah/yq#install"
    exit 1
fi
echo "  ✅ yq found: $(which yq)"

# Check for docker
if ! command -v docker &> /dev/null; then
    echo "❌ Error: Docker is required but not installed"
    echo "   Install from: https://docs.docker.com/get-docker/"
    exit 1
fi
echo "  ✅ docker found: $(which docker)"

echo ""

# ========================================
# Validate Input Files
# ========================================
echo "📂 Validating input files..."

if [ ! -d "$GENESIS_DIR" ]; then
    echo "❌ Error: Genesis directory not found: $GENESIS_DIR"
    exit 1
fi
echo "  ✅ Genesis directory: $GENESIS_DIR"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Error: config.yaml not found at $CONFIG_FILE"
    exit 1
fi
echo "  ✅ config.yaml found"

if [ ! -f "$VALIDATOR_CONFIG_FILE" ]; then
    echo "❌ Error: validator-config.yaml not found at $VALIDATOR_CONFIG_FILE"
    exit 1
fi
echo "  ✅ validator-config.yaml found"

echo ""

# Convert to absolute paths early for use throughout the script
GENESIS_DIR_ABS="$(cd "$GENESIS_DIR" && pwd)"
PARENT_DIR_ABS="$(cd "$GENESIS_DIR/.." && pwd)"

# ========================================
# Step 1: Generate Hash-Sig Validator Keys
# ========================================
echo "🔐 Step 1: Generating hash-sig validator keys..."

# Determine the number of validators
VALIDATOR_COUNT=$(yq eval '.VALIDATOR_COUNT' "$CONFIG_FILE")
if [ -z "$VALIDATOR_COUNT" ] || [ "$VALIDATOR_COUNT" == "null" ]; then
    # Count validators from validator-config.yaml
    VALIDATOR_COUNT=$(yq eval '.validators | length' "$VALIDATOR_CONFIG_FILE")
fi

echo "   Number of validators: $VALIDATOR_COUNT"

# Path to hash-sig CLI binary (from git submodule)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HASHSIG_CLI_DIR="$SCRIPT_DIR/tools/hash-sig-cli"
HASHSIG_CLI="$HASHSIG_CLI_DIR/target/release/hashsig"

# Check if hash-sig submodule exists
if [ ! -d "$HASHSIG_CLI_DIR" ]; then
    echo "   ❌ Error: hash-sig-cli submodule not found at $HASHSIG_CLI_DIR"
    echo "   Please initialize the submodule:"
    echo "   cd $SCRIPT_DIR && git submodule add https://github.com/blockblaz/hash-sig-cli.git tools/hash-sig-cli"
    echo "   cd tools/hash-sig-cli && git submodule update --init --recursive"
    exit 1
fi

# Check if hash-sig CLI binary exists, build if needed
if [ ! -f "$HASHSIG_CLI" ]; then
    echo "   ⚠️  Hash-sig CLI binary not found"
    echo "   Building hash-sig CLI from submodule..."
    (cd "$HASHSIG_CLI_DIR" && cargo build --release)
    
    if [ ! -f "$HASHSIG_CLI" ]; then
        echo "   ❌ Error: Failed to build hash-sig CLI"
        exit 1
    fi
fi

echo "   ✅ Hash-sig CLI found: $HASHSIG_CLI"

# Create hash-sig keys directory
HASH_SIG_KEYS_DIR="$GENESIS_DIR_ABS/hash-sig-keys"
mkdir -p "$HASH_SIG_KEYS_DIR"

# Generate hash-sig keys for all validators
echo "   Generating keys for $VALIDATOR_COUNT validators..."
"$HASHSIG_CLI" generate-for-genesis \
    --num-validators "$VALIDATOR_COUNT" \
    --log-num-active-epochs 18 \
    --output-dir "$HASH_SIG_KEYS_DIR"

if [ $? -ne 0 ]; then
    echo ""
    echo "   ❌ Error: Hash-sig key generation failed!"
    exit 1
fi

echo ""
echo "   ✅ Generated $VALIDATOR_COUNT validator key pairs"
echo "   ✅ Keys saved to: $HASH_SIG_KEYS_DIR"
echo ""

# ========================================
# Step 2: Update Genesis Time
# ========================================
echo "⏰ Step 2: Updating genesis time..."
TIME_NOW="$(date +%s)"
GENESIS_TIME=$((TIME_NOW + 30))

# Use yq for cross-platform compatibility
yq eval ".GENESIS_TIME = $GENESIS_TIME" -i "$CONFIG_FILE"

echo "   ✅ Genesis time set to: $GENESIS_TIME"
echo ""

# ========================================
# Step 3: Run PK's Genesis Generator
# ========================================
echo "🔧 Step 3: Running PK's eth-beacon-genesis tool..."
echo "   Docker image: $PK_DOCKER_IMAGE"
echo "   Command: leanchain"
echo ""

# Run PK's tool (GENESIS_DIR_ABS and PARENT_DIR_ABS already defined above)
# Note: PK's tool expects parent directory as mount point
echo "   Executing docker command..."

docker run --rm \
  -v "$PARENT_DIR_ABS:/data" \
  "$PK_DOCKER_IMAGE" \
  leanchain \
  --config "/data/genesis/config.yaml" \
  --mass-validators "/data/genesis/validator-config.yaml" \
  --state-output "/data/genesis/genesis.ssz" \
  --json-output "/data/genesis/genesis.json" \
  --nodes-output "/data/genesis/nodes.yaml" \
  --validators-output "/data/genesis/validators.yaml" \
  --config-output "/data/genesis/config.yaml"

if [ $? -ne 0 ]; then
    echo ""
    echo "❌ Error: PK's genesis generator failed!"
    exit 1
fi

echo ""
echo "   ✅ PK's tool completed successfully"
echo "   ✅ Generated: config.yaml (updated)"
echo "   ✅ Generated: validators.yaml"
echo "   ✅ Generated: nodes.yaml"
echo "   ✅ Generated: genesis.json"
echo "   ✅ Generated: genesis.ssz"
echo ""

# ========================================
# Step 4: Generate Private Key Files (for ENR)
# ========================================
echo "🔑 Step 4: Generating private key files (for ENR)..."

# Extract node names from validator-config.yaml
NODE_NAMES=($(yq eval '.validators[].name' "$VALIDATOR_CONFIG_FILE"))

if [ ${#NODE_NAMES[@]} -eq 0 ]; then
    echo "❌ Error: No validators found in $VALIDATOR_CONFIG_FILE"
    exit 1
fi

echo "  Nodes: ${NODE_NAMES[@]}"

for node in "${NODE_NAMES[@]}"; do
    privkey=$(yq eval ".validators[] | select(.name == \"$node\") | .privkey" "$VALIDATOR_CONFIG_FILE")
    
    if [ "$privkey" == "null" ] || [ -z "$privkey" ]; then
        echo "  ⚠️  Node $node: No privkey found, skipping"
        continue
    fi
    
    key_file="$GENESIS_DIR/$node.key"
    echo "$privkey" > "$key_file"
    echo "  ✅ Generated: $node.key"
done

echo ""

# ========================================
# Step 5: Validate Generated Files
# ========================================
echo "✓ Step 5: Validating generated files..."

required_files=("config.yaml" "validators.yaml" "nodes.yaml" "genesis.json" "genesis.ssz")
all_good=true

for file in "${required_files[@]}"; do
    if [ -f "$GENESIS_DIR/$file" ]; then
        echo "  ✅ $file exists"
    else
        echo "  ❌ $file is missing"
        all_good=false
    fi
done

if [ "$all_good" = false ]; then
    echo ""
    echo "❌ Some required files are missing!"
    exit 1
fi

echo ""

# ========================================
# Summary
# ========================================
echo "✅ Genesis generation complete!"
echo ""
echo "📄 Generated files:"
echo "   $GENESIS_DIR/config.yaml (updated)"
echo "   $GENESIS_DIR/validators.yaml"
echo "   $GENESIS_DIR/nodes.yaml"
echo "   $GENESIS_DIR/genesis.json"
echo "   $GENESIS_DIR/genesis.ssz"
for node in "${NODE_NAMES[@]}"; do
    if [ -f "$GENESIS_DIR/$node.key" ]; then
        echo "   $GENESIS_DIR/$node.key"
    fi
done
echo ""
echo "🔐 Hash-Sig Validator Keys:"
echo "   $GENESIS_DIR/hash-sig-keys/validator-keys-manifest.yaml"
for i in $(seq 0 $((VALIDATOR_COUNT - 1))); do
    echo "   $GENESIS_DIR/hash-sig-keys/validator_${i}_pk.json"
    echo "   $GENESIS_DIR/hash-sig-keys/validator_${i}_sk.json"
done
echo ""
echo "🎯 Next steps:"
echo "   Run your nodes with: NETWORK_DIR=local-devnet ./spin-node.sh --node all --generateGenesis"
echo ""
echo "ℹ️  Using PK's eth-beacon-genesis docker image:"
echo "   Image: $PK_DOCKER_IMAGE"
echo "   PR: https://github.com/ethpandaops/eth-beacon-genesis/pull/36"
echo ""
echo "ℹ️  Hash-sig keys generated with:"
echo "   Scheme: SIGTopLevelTargetSumLifetime32Dim64Base8"
echo "   Active Epochs: 2^18 (262,144)"
echo "   Total Lifetime: 2^32 (4,294,967,296)"
echo ""
