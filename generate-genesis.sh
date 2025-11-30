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
                       - validator-config.yaml (with node configurations and individual counts)
                       - validator-config.yaml must include key: config.activeEpoch (positive integer)

Example:
  $0 local-devnet/genesis

Generated Files:
  - config.yaml        Auto-generated with GENESIS_TIME, VALIDATOR_COUNT, shuffle, and config.activeEpoch
  - validators.yaml    Validator index assignments for each node
  - nodes.yaml         ENR (Ethereum Node Records) for peer discovery
  - genesis.json       Genesis state in JSON format
  - genesis.ssz        Genesis state in SSZ format
  - <node>.key         Private key files for each node

How It Works:
  1. Calculates GENESIS_TIME (current time + 30 seconds)
  2. Reads individual validator 'count' fields from validator-config.yaml
  3. Reads config.activeEpoch from validator-config.yaml (required)
  4. Automatically sums them to calculate total VALIDATOR_COUNT
  5. Generates config.yaml from scratch with calculated values including config.activeEpoch
  6. Runs PK's genesis generator with correct parameters

Note: config.yaml is a generated file - only edit validator-config.yaml

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

# Parse optional --skipKeyGen flag, default true
SKIP_KEY_GEN="true"
shift
while [[ $# -gt 0 ]]; do
    case "$1" in
        --forceKeyGen)
            SKIP_KEY_GEN="false"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

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

# Hash-sig-cli Docker image
HASH_SIG_CLI_IMAGE="blockblaz/hash-sig-cli:devnet1"
echo "  ✅ Using hash-sig-cli Docker image: $HASH_SIG_CLI_IMAGE"

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

if [ ! -f "$VALIDATOR_CONFIG_FILE" ]; then
    echo "❌ Error: validator-config.yaml not found at $VALIDATOR_CONFIG_FILE"
    exit 1
fi
echo "  ✅ validator-config.yaml found"

echo ""

# ========================================
# Step 1: Generate Hash-Sig Validator Keys
# ========================================
echo "🔐 Step 1: Generating hash-sig validator keys..."

# Create hash-sig keys directory
HASH_SIG_KEYS_DIR="$GENESIS_DIR/hash-sig-keys"
mkdir -p "$HASH_SIG_KEYS_DIR"

# Count total validators from validator-config.yaml
VALIDATOR_COUNT=$(yq eval '.validators | length' "$VALIDATOR_CONFIG_FILE")

if [ -z "$VALIDATOR_COUNT" ] || [ "$VALIDATOR_COUNT" == "null" ] || [ "$VALIDATOR_COUNT" -eq 0 ]; then
    echo "❌ Error: Could not determine validator count from $VALIDATOR_CONFIG_FILE"
    exit 1
fi

# Check if keys already exist
MANIFEST_FILE="$HASH_SIG_KEYS_DIR/validator-keys-manifest.yaml"
KEYS_EXIST=true
if [ ! -f "$MANIFEST_FILE" ]; then
    KEYS_EXIST=false
else
    for ((i=0; i<VALIDATOR_COUNT; i++)); do
        if [ ! -f "$HASH_SIG_KEYS_DIR/validator_${i}_pk.json" ] || \
           [ ! -f "$HASH_SIG_KEYS_DIR/validator_${i}_sk.json" ]; then
            KEYS_EXIST=false
            break
        fi
    done
fi

echo "SKIP_KEY_GEN=$SKIP_KEY_GEN"
echo "KEYS_EXIST=$KEYS_EXIST"

# Determine if we should skip key generation
if [ "$SKIP_KEY_GEN" == "false" ]; then
    SHOULD_SKIP=false
elif [ "$SKIP_KEY_GEN" == "true" ] && [ "$KEYS_EXIST" == "true" ]; then
    SHOULD_SKIP=true
else
    SHOULD_SKIP=false
fi

# Read required active epoch exponent from validator-config.yaml
ACTIVE_EPOCH=$(yq eval '.config.activeEpoch' "$VALIDATOR_CONFIG_FILE" 2>/dev/null)
if [ "$ACTIVE_EPOCH" == "null" ] || [ -z "$ACTIVE_EPOCH" ]; then
    echo "❌ Error: validator-config.yaml missing valid key config.activeEpoch (positive integer required)" >&2
    exit 1
fi
if ! [[ "$ACTIVE_EPOCH" =~ ^[0-9]+$ ]] || [ "$ACTIVE_EPOCH" -le 0 ]; then
    echo "❌ Error: validator-config.yaml missing valid key config.activeEpoch (positive integer required)" >&2
    exit 1
fi

if [ "$SHOULD_SKIP" == "true" ]; then
    echo "   ⏭️  Skipping key generation - keys already present"
    echo "   Key directory: $HASH_SIG_KEYS_DIR"
    echo ""
else
    echo "   Generating keys for $VALIDATOR_COUNT validators..."
    echo "   Using scheme: SIGTopLevelTargetSumLifetime32Dim64Base8"
    echo "   Key directory: $HASH_SIG_KEYS_DIR"
    echo ""

    # Generate hash-sig keys for all validators using Docker
    # Scheme: SIGTopLevelTargetSumLifetime32Dim64Base8
    # Active epochs: 2^ACTIVE_EPOCH (from validator-config.yaml)
    # Total lifetime: 2^32 (4,294,967,296)
    # Convert to absolute path for Docker volume mounting
    GENESIS_DIR_ABS="$(cd "$GENESIS_DIR" && pwd)"

    # Get current user ID and group ID to avoid permission issues
    CURRENT_UID=$(id -u)
    CURRENT_GID=$(id -g)

    docker run --rm \
      --user "$CURRENT_UID:$CURRENT_GID" \
      -v "$GENESIS_DIR_ABS:/genesis" \
      "$HASH_SIG_CLI_IMAGE" \
      generate \
      --num-validators "$VALIDATOR_COUNT" \
      --log-num-active-epochs "$ACTIVE_EPOCH" \
      --output-dir "/genesis/hash-sig-keys"

    if [ $? -ne 0 ]; then
        echo "   ❌ Failed to generate hash-sig keys"
        exit 1
    fi

    echo "   ✅ Generated keys for $VALIDATOR_COUNT validators"
    echo "   ✅ Files created:"
    for i in $(seq 0 $((VALIDATOR_COUNT - 1))); do
        echo "      - validator_${i}_pk.json and validator_${i}_sk.json"
    done

    echo ""
    echo "   ✅ Hash-sig key generation complete!"
    echo ""
fi

# ========================================
# Verify validator-keys-manifest.yaml
# ========================================
echo "🔧 Verifying validator-keys-manifest.yaml..."

MANIFEST_FILE="$HASH_SIG_KEYS_DIR/validator-keys-manifest.yaml"

# Check if manifest file exists (critical - exit if missing)
if [ ! -f "$MANIFEST_FILE" ]; then
    echo "   ❌ Error: validator-keys-manifest.yaml not found at $MANIFEST_FILE"
    echo "   This file is required for validator key management"
    exit 1
fi

# Detect the field name used by hash-sig-cli (pubkey_hex, public_key_file, or publicKey)
# Check first validator entry to determine field name
FIRST_VALIDATOR_FIELDS=$(yq eval '.validators[0] | keys | .[]' "$MANIFEST_FILE" 2>/dev/null)
PUBKEY_FIELD=""
if echo "$FIRST_VALIDATOR_FIELDS" | grep -q "pubkey_hex"; then
    PUBKEY_FIELD="pubkey_hex"
elif echo "$FIRST_VALIDATOR_FIELDS" | grep -q "public_key_file"; then
    PUBKEY_FIELD="public_key_file"
elif echo "$FIRST_VALIDATOR_FIELDS" | grep -q "publicKey"; then
    PUBKEY_FIELD="publicKey"
else
    echo "   ❌ Error: Could not determine pubkey field name in manifest"
    echo "   Expected 'pubkey_hex', 'public_key_file', or 'publicKey' field"
    exit 1
fi

# Verify that manifest contains hex bytes (not file names)
FIRST_PUBKEY=$(yq eval ".validators[0].$PUBKEY_FIELD" "$MANIFEST_FILE" 2>/dev/null)
if [ -z "$FIRST_PUBKEY" ]; then
    echo "   ❌ Error: Could not read pubkey from manifest"
    exit 1
fi

# Check if it's hex format (starts with 0x)
if [[ ! "$FIRST_PUBKEY" =~ ^0x[0-9a-fA-F]+$ ]]; then
    echo "   ❌ Error: Manifest does not contain hex pubkeys"
    echo "   Found: $FIRST_PUBKEY"
    echo "   Expected format: 0x[hex bytes]"
    echo "   Make sure hash-sig-cli generates manifest with hex bytes"
    exit 1
fi

echo "   ✅ Manifest verified - contains hex pubkeys"
echo "   Detected pubkey field: $PUBKEY_FIELD"

echo ""

# ========================================
# Step 2: Generate config.yaml
# ========================================
echo "🔧 Step 2: Generating config.yaml..."

# Calculate genesis time (30 seconds from now)
TIME_NOW="$(date +%s)"
GENESIS_TIME=$((TIME_NOW + 30))
echo "   Genesis time: $GENESIS_TIME"

# Sum all individual validator counts from validator-config.yaml
TOTAL_VALIDATORS=$(yq eval '.validators[].count' "$VALIDATOR_CONFIG_FILE" | awk '{sum+=$1} END {print sum}')

# Validate the sum
if [ -z "$TOTAL_VALIDATORS" ] || [ "$TOTAL_VALIDATORS" == "null" ]; then
    echo "❌ Error: Could not calculate total validator count from $VALIDATOR_CONFIG_FILE"
    echo "   Make sure each validator has a 'count' field defined"
    exit 1
fi

if [ "$TOTAL_VALIDATORS" -eq 0 ]; then
    echo "❌ Error: Total validator count is 0"
    echo "   Check that validator count values are greater than 0 in $VALIDATOR_CONFIG_FILE"
    exit 1
fi

# Display individual validator counts for transparency
echo "   Individual validator counts:"
while IFS= read -r line; do
    validator_name=$(echo "$line" | cut -d: -f1)
    validator_count=$(echo "$line" | cut -d: -f2 | xargs)
    echo "     - $validator_name: $validator_count"
done < <(yq eval '.validators[] | .name + ":" + (.count | tostring)' "$VALIDATOR_CONFIG_FILE")

echo "   Total validator count: $TOTAL_VALIDATORS"

# Generate config.yaml from scratch
cat > "$CONFIG_FILE" << EOF
# Genesis Settings
GENESIS_TIME: $GENESIS_TIME

# Key Settings
ACTIVE_EPOCH: $ACTIVE_EPOCH

# Validator Settings  
VALIDATOR_COUNT: $TOTAL_VALIDATORS
EOF

echo "   ✅ Generated config.yaml"
echo ""

# ========================================
# Step 3: Run PK's Genesis Generator
# ========================================
echo "🔧 Step 3: Running PK's eth-beacon-genesis tool..."
echo "   Docker image: $PK_DOCKER_IMAGE"
echo "   Command: leanchain"
echo ""

# Convert to absolute path for docker volume mount
GENESIS_DIR_ABS="$(cd "$GENESIS_DIR" && pwd)"
PARENT_DIR_ABS="$(cd "$GENESIS_DIR/.." && pwd)"

# Get current user ID and group ID to avoid permission issues
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)

# Run PK's tool
# Note: PK's tool expects parent directory as mount point
echo "   Executing docker command..."

docker run --rm --pull=always \
  --user "$CURRENT_UID:$CURRENT_GID" \
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
# Add genesis_validators to config.yaml
# ========================================
echo "🔧 Adding genesis_validators to config.yaml..."

# Calculate cumulative validator indices
CUMULATIVE_INDEX=0
VALIDATOR_ENTRY_INDEX=0

# Create temporary file for genesis_validators YAML
GENESIS_VALIDATORS_TMP=$(mktemp)

# Iterate through validators in validator-config.yaml
while IFS= read -r validator_name; do
    COUNT=$(yq eval ".validators[$VALIDATOR_ENTRY_INDEX].count" "$VALIDATOR_CONFIG_FILE")
    
    # Read hex pubkey directly from manifest (hash-sig-cli now generates hex)
    PUBKEY_HEX=$(yq eval ".validators[$VALIDATOR_ENTRY_INDEX].$PUBKEY_FIELD" "$MANIFEST_FILE" 2>/dev/null)
    
    if [ -z "$PUBKEY_HEX" ] || [ "$PUBKEY_HEX" == "null" ]; then
        echo "   ❌ Error: Could not read pubkey for validator $VALIDATOR_ENTRY_INDEX from manifest"
        rm -f "$GENESIS_VALIDATORS_TMP"
        exit 1
    fi
    
    # Verify it's hex format
    if [[ ! "$PUBKEY_HEX" =~ ^0x[0-9a-fA-F]+$ ]]; then
        echo "   ❌ Error: Invalid pubkey format for validator $VALIDATOR_ENTRY_INDEX"
        echo "   Found: $PUBKEY_HEX"
        echo "   Expected format: 0x[hex bytes]"
        rm -f "$GENESIS_VALIDATORS_TMP"
        exit 1
    fi
    
    # For each validator index this entry represents
    for ((idx=0; idx<COUNT; idx++)); do
        ACTUAL_INDEX=$((CUMULATIVE_INDEX + idx))
        # Build YAML structure in temp file
        # strip 0x from PUBKEY_HEX
        echo "    - \"${PUBKEY_HEX#0x}\"" >> "$GENESIS_VALIDATORS_TMP"
    done
    
    CUMULATIVE_INDEX=$((CUMULATIVE_INDEX + COUNT))
    VALIDATOR_ENTRY_INDEX=$((VALIDATOR_ENTRY_INDEX + 1))
done < <(yq eval '.validators[].name' "$VALIDATOR_CONFIG_FILE")

# Merge genesis_validators into config.yaml using yq
if [ -s "$GENESIS_VALIDATORS_TMP" ]; then
    # Build a temporary YAML file with just genesis_validators
    GENESIS_VALIDATORS_YAML=$(mktemp)
    echo "GENESIS_VALIDATORS:" > "$GENESIS_VALIDATORS_YAML"
    cat "$GENESIS_VALIDATORS_TMP" >> "$GENESIS_VALIDATORS_YAML"
    
    # Use yq to merge the genesis_validators into config.yaml
    yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' -i "$CONFIG_FILE" "$GENESIS_VALIDATORS_YAML" 2>/dev/null || {
        # Fallback: append manually if yq merge fails
        echo "" >> "$CONFIG_FILE"
        cat "$GENESIS_VALIDATORS_YAML" >> "$CONFIG_FILE"
    }
    rm -f "$GENESIS_VALIDATORS_YAML"
    echo "   ✅ Added genesis_validators to config.yaml"
else
    echo "   ⚠️  Warning: No genesis_validators to add"
fi

# Clean up temp file
rm -f "$GENESIS_VALIDATORS_TMP"

echo ""

# ========================================
# Step 4: Generate Private Key Files
# ========================================
echo "🔑 Step 4: Generating private key files..."

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
echo "   Docker Image: $HASH_SIG_CLI_IMAGE"
echo "   Scheme: SIGTopLevelTargetSumLifetime32Dim64Base8"
echo "   Active Epochs: 2^$ACTIVE_EPOCH"
echo "   Total Lifetime: 2^32 (4,294,967,296)"
echo ""
