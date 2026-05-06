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
Usage: $0 <genesis-directory> [--mode local|ansible] [--offset <seconds>] [--forceKeyGen] [--validator-config <path>]

Generate genesis configuration files using PK's eth-beacon-genesis tool.
Generates: config.yaml, validators.yaml, nodes.yaml, genesis.json, genesis.ssz, and .key files

Arguments:
  genesis-directory    Path to the genesis directory containing:
                       - validator-config.yaml (with node configurations and individual counts)
                       - validator-config.yaml must include key: config.activeEpoch (positive integer)

Options:
  --mode <mode>        Deployment mode: 'local' or 'ansible' (default: local)
                       - local: GENESIS_TIME = now + 30 seconds (default)
                       - ansible: GENESIS_TIME = now + 360 seconds (default)
  --offset <seconds>   Override genesis time offset in seconds (overrides mode defaults)
  --forceKeyGen        Force regeneration of hash-sig validator keys
  --validator-config   Path to a custom validator-config.yaml (default: <genesis-directory>/validator-config.yaml)

Examples:
  $0 local-devnet/genesis                      # Local mode (30s offset)
  $0 ansible-devnet/genesis --mode ansible     # Ansible mode (360s offset)
  $0 ansible-devnet/genesis --mode ansible --offset 600  # Custom 600s offset

Generated Files:
  - config.yaml        Auto-generated with GENESIS_TIME, VALIDATOR_COUNT, shuffle, and config.activeEpoch
  - validators.yaml    Validator index assignments for each node
  - nodes.yaml         ENR (Ethereum Node Records) for peer discovery
  - genesis.json       Genesis state in JSON format
  - genesis.ssz        Genesis state in SSZ format
  - <node>.key         Private key files for each node

How It Works:
  1. Calculates GENESIS_TIME based on --mode (local: +30s, ansible: +360s) or --offset if provided
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

# Parse optional flags
SKIP_KEY_GEN="true"
DEPLOYMENT_MODE="local"  # Default to local mode
GENESIS_TIME_OFFSET=""   # Will be set based on mode or --offset flag
shift
while [[ $# -gt 0 ]]; do
    case "$1" in
        --forceKeyGen)
            SKIP_KEY_GEN="false"
            shift
            ;;
        --mode)
            if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                DEPLOYMENT_MODE="$2"
                shift 2
            else
                echo "❌ Error: --mode requires a value (local or ansible)"
                exit 1
            fi
            ;;
        --offset)
            if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    echo "❌ Error: --offset requires a positive integer"
                    exit 1
                fi
                GENESIS_TIME_OFFSET="$2"
                shift 2
            else
                echo "❌ Error: --offset requires a value (positive integer)"
                exit 1
            fi
            ;;
        --validator-config)
            if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                VALIDATOR_CONFIG_FILE="$2"
                shift 2
            else
                echo "❌ Error: --validator-config requires a path"
                exit 1
            fi
            ;;
        *)
            shift
            ;;
    esac
done

# Validate deployment mode
if [ "$DEPLOYMENT_MODE" != "local" ] && [ "$DEPLOYMENT_MODE" != "ansible" ]; then
    echo "❌ Error: Invalid deployment mode '$DEPLOYMENT_MODE'. Must be 'local' or 'ansible'"
    exit 1
fi

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

# Hash-sig-cli Docker image (separate attester + proposer keys per validator when using dual-key manifest)
HASH_SIG_CLI_IMAGE="blockblaz/hash-sig-cli:latest"
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
VALIDATOR_COUNT=$(yq eval '.validators[].count' "$VALIDATOR_CONFIG_FILE" | awk '{sum+=$1} END {print sum}')

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
        # devnet4+: proposer + attester key files per index
        if [ -f "$HASH_SIG_KEYS_DIR/validator_${i}_proposer_key_pk.json" ] && \
           [ -f "$HASH_SIG_KEYS_DIR/validator_${i}_attester_key_pk.json" ]; then
            if [ ! -f "$HASH_SIG_KEYS_DIR/validator_${i}_proposer_key_sk.json" ] || \
               [ ! -f "$HASH_SIG_KEYS_DIR/validator_${i}_attester_key_sk.json" ]; then
                KEYS_EXIST=false
                break
            fi
        elif [ -f "$HASH_SIG_KEYS_DIR/validator_${i}_pk.json" ] && \
             [ -f "$HASH_SIG_KEYS_DIR/validator_${i}_sk.json" ]; then
            :
        else
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

    # Pull latest image first
    docker pull "$HASH_SIG_CLI_IMAGE" || true

    docker run --rm --pull=never \
      --user "$CURRENT_UID:$CURRENT_GID" \
      -v "$GENESIS_DIR_ABS:/genesis" \
      "$HASH_SIG_CLI_IMAGE" \
      generate \
      --num-validators "$VALIDATOR_COUNT" \
      --log-num-active-epochs "$ACTIVE_EPOCH" \
      --output-dir "/genesis/hash-sig-keys" \
      --export-format both

    if [ $? -ne 0 ]; then
        echo "   ❌ Failed to generate hash-sig keys"
        exit 1
    fi

    echo "   ✅ Generated keys for $VALIDATOR_COUNT validators"
    echo "   ✅ Files created (per validator: proposer + attester pk/sk):"
    for i in $(seq 0 $((VALIDATOR_COUNT - 1))); do
        echo "      - validator_${i}_proposer_key_{pk,sk}.json validator_${i}_attester_key_{pk,sk}.json"
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

# Detect dual-key manifest (hash-sig-cli) vs legacy single pubkey_hex
FIRST_VALIDATOR_FIELDS=$(yq eval '.validators[0] | keys | .[]' "$MANIFEST_FILE" 2>/dev/null)
DUAL_KEY_MODE=false
PUBKEY_FIELD=""
if echo "$FIRST_VALIDATOR_FIELDS" | grep -q "attester_key_pubkey_hex" && \
   echo "$FIRST_VALIDATOR_FIELDS" | grep -q "proposer_key_pubkey_hex"; then
    DUAL_KEY_MODE=true
elif echo "$FIRST_VALIDATOR_FIELDS" | grep -q "pubkey_hex"; then
    PUBKEY_FIELD="pubkey_hex"
elif echo "$FIRST_VALIDATOR_FIELDS" | grep -q "public_key_file"; then
    PUBKEY_FIELD="public_key_file"
elif echo "$FIRST_VALIDATOR_FIELDS" | grep -q "publicKey"; then
    PUBKEY_FIELD="publicKey"
else
    echo "   ❌ Error: Could not determine manifest pubkey layout"
    echo "   Expected dual keys (attester_key_pubkey_hex + proposer_key_pubkey_hex) or legacy pubkey_hex / public_key_file / publicKey"
    exit 1
fi

if [ "$DUAL_KEY_MODE" = true ]; then
    ATTEST_PUB=$(yq eval '.validators[0].attester_key_pubkey_hex' "$MANIFEST_FILE" 2>/dev/null)
    PROP_PUB=$(yq eval '.validators[0].proposer_key_pubkey_hex' "$MANIFEST_FILE" 2>/dev/null)
    if [ -z "$ATTEST_PUB" ] || [ -z "$PROP_PUB" ]; then
        echo "   ❌ Error: Could not read attester/proposer pubkeys from manifest"
        exit 1
    fi
    for pk in "$ATTEST_PUB" "$PROP_PUB"; do
        if [[ ! "$pk" =~ ^0x[0-9a-fA-F]+$ ]]; then
            echo "   ❌ Error: Manifest does not contain hex pubkeys (dual-key mode)"
            echo "   Found: $pk"
            exit 1
        fi
    done
    echo "   ✅ Manifest verified - dual-key format (attester + proposer)"
else
    FIRST_PUBKEY=$(yq eval ".validators[0].$PUBKEY_FIELD" "$MANIFEST_FILE" 2>/dev/null)
    if [ -z "$FIRST_PUBKEY" ]; then
        echo "   ❌ Error: Could not read pubkey from manifest"
        exit 1
    fi
    if [[ ! "$FIRST_PUBKEY" =~ ^0x[0-9a-fA-F]+$ ]]; then
        echo "   ❌ Error: Manifest does not contain hex pubkeys"
        echo "   Found: $FIRST_PUBKEY"
        echo "   Expected format: 0x[hex bytes]"
        exit 1
    fi
    echo "   ✅ Manifest verified - contains hex pubkeys (legacy)"
    echo "   Detected pubkey field: $PUBKEY_FIELD"
fi

echo ""

# ========================================
# Step 2: Generate config.yaml
# ========================================
echo "🔧 Step 2: Generating config.yaml..."

# Calculate genesis time based on deployment mode or explicit offset
# Default offsets: Local mode: 30 seconds, Ansible mode: 360 seconds
TIME_NOW="$(date +%s)"
if [ -n "$GENESIS_TIME_OFFSET" ]; then
    # Use explicit offset if provided
    :
elif [ "$DEPLOYMENT_MODE" == "local" ]; then
    GENESIS_TIME_OFFSET=30
else
    GENESIS_TIME_OFFSET=360
fi
GENESIS_TIME=$((TIME_NOW + GENESIS_TIME_OFFSET))
echo "   Deployment mode: $DEPLOYMENT_MODE"
echo "   Genesis time offset: ${GENESIS_TIME_OFFSET}s"
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
while IFS= read -r validator_name; do
    # Use simple yq expression per validator to avoid cross-version quirks
    validator_count=$(yq eval ".validators[] | select(.name == \"$validator_name\") | .count" "$VALIDATOR_CONFIG_FILE")
    echo "     - $validator_name: $validator_count"
done < <(yq eval '.validators[].name' "$VALIDATOR_CONFIG_FILE")

echo "   Total validator count: $TOTAL_VALIDATORS"

# Optional chain setting; default matches leanSpec ATTESTATION_COMMITTEE_COUNT (Uint64(1))
ATTESTATION_COMMITTEE_COUNT=$(yq eval '.config.attestation_committee_count // 1' "$VALIDATOR_CONFIG_FILE" 2>/dev/null)
if [ -z "$ATTESTATION_COMMITTEE_COUNT" ] || [ "$ATTESTATION_COMMITTEE_COUNT" == "null" ]; then
    ATTESTATION_COMMITTEE_COUNT=1
fi

# Generate config.yaml from scratch
cat > "$CONFIG_FILE" << EOF
# Genesis Settings
GENESIS_TIME: $GENESIS_TIME

# Chain Settings
ATTESTATION_COMMITTEE_COUNT: $ATTESTATION_COMMITTEE_COUNT

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

# If validator config is external (not already inside genesis dir), copy it in
# so the Docker container can find it at the expected /data/genesis/validator-config.yaml path
GENESIS_VALIDATOR_CONFIG="$GENESIS_DIR/validator-config.yaml"
if [ "$VALIDATOR_CONFIG_FILE" != "$GENESIS_VALIDATOR_CONFIG" ]; then
    cp "$VALIDATOR_CONFIG_FILE" "$GENESIS_VALIDATOR_CONFIG"
    echo "   Copied external validator config to genesis dir"
fi

# Convert to absolute path for docker volume mount
GENESIS_DIR_ABS="$(cd "$GENESIS_DIR" && pwd)"
PARENT_DIR_ABS="$(cd "$GENESIS_DIR/.." && pwd)"

# Get current user ID and group ID to avoid permission issues
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)

# Run PK's tool
# Note: PK's tool expects parent directory as mount point
echo "   Executing docker command..."

# Pull latest image first 
echo "   Pulling latest image: $PK_DOCKER_IMAGE"
docker pull "$PK_DOCKER_IMAGE" || true

docker run --rm --pull=never \
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

# Debug: show manifest file and layout
echo "   Reading pubkeys from: $MANIFEST_FILE"
if [ "$DUAL_KEY_MODE" = true ]; then
    echo "   Layout: dual-key (attestation_pubkey + proposal_pubkey in config.yaml)"
else
    echo "   Using pubkey field: $PUBKEY_FIELD"
fi

# Iterate through validators in validator-config.yaml
while IFS= read -r validator_name; do
    COUNT=$(yq eval ".validators[$VALIDATOR_ENTRY_INDEX].count" "$VALIDATOR_CONFIG_FILE")
    echo "   Node $VALIDATOR_ENTRY_INDEX ($validator_name): count=$COUNT"

    # For each global validator index this node owns
    for ((idx=0; idx<COUNT; idx++)); do
        ACTUAL_INDEX=$((CUMULATIVE_INDEX + idx))
        if [ "$DUAL_KEY_MODE" = true ]; then
            AH=$(yq eval ".validators[$ACTUAL_INDEX].attester_key_pubkey_hex" "$MANIFEST_FILE" 2>/dev/null)
            PH=$(yq eval ".validators[$ACTUAL_INDEX].proposer_key_pubkey_hex" "$MANIFEST_FILE" 2>/dev/null)
            echo "      index $ACTUAL_INDEX: attester=${AH:0:12}..., proposer=${PH:0:12}..."
            if [ -z "$AH" ] || [ "$AH" == "null" ] || [ -z "$PH" ] || [ "$PH" == "null" ]; then
                echo "   ❌ Error: Could not read attester/proposer pubkeys for manifest index $ACTUAL_INDEX"
                rm -f "$GENESIS_VALIDATORS_TMP"
                exit 1
            fi
            for pk in "$AH" "$PH"; do
                if [[ ! "$pk" =~ ^0x[0-9a-fA-F]+$ ]]; then
                    echo "   ❌ Error: Invalid pubkey format for validator index $ACTUAL_INDEX"
                    echo "   Found: $pk"
                    rm -f "$GENESIS_VALIDATORS_TMP"
                    exit 1
                fi
            done
            echo "  - attestation_pubkey: \"${AH#0x}\"" >> "$GENESIS_VALIDATORS_TMP"
            echo "    proposal_pubkey: \"${PH#0x}\"" >> "$GENESIS_VALIDATORS_TMP"
        else
            PK=$(yq eval ".validators[$ACTUAL_INDEX].$PUBKEY_FIELD" "$MANIFEST_FILE" 2>/dev/null)
            echo "      index $ACTUAL_INDEX: pubkey=${PK:0:20}..."
            if [ -z "$PK" ] || [ "$PK" == "null" ]; then
                echo "   ❌ Error: Could not read pubkey for manifest index $ACTUAL_INDEX"
                rm -f "$GENESIS_VALIDATORS_TMP"
                exit 1
            fi
            if [[ ! "$PK" =~ ^0x[0-9a-fA-F]+$ ]]; then
                echo "   ❌ Error: Invalid pubkey format for validator index $ACTUAL_INDEX"
                echo "   Found: $PK"
                rm -f "$GENESIS_VALIDATORS_TMP"
                exit 1
            fi
            echo "    - \"${PK#0x}\"" >> "$GENESIS_VALIDATORS_TMP"
        fi
    done

    CUMULATIVE_INDEX=$((CUMULATIVE_INDEX + COUNT))
    VALIDATOR_ENTRY_INDEX=$((VALIDATOR_ENTRY_INDEX + 1))
done < <(yq eval '.validators[].name' "$VALIDATOR_CONFIG_FILE")

# Append genesis_validators to config.yaml
if [ -s "$GENESIS_VALIDATORS_TMP" ]; then
    # Append directly to config.yaml (simpler and more reliable than yq merge)
    echo "" >> "$CONFIG_FILE"
    echo "# List of Genesis Validators' Public Keys (attestation + proposal)" >> "$CONFIG_FILE"
    echo "GENESIS_VALIDATORS:" >> "$CONFIG_FILE"
    cat "$GENESIS_VALIDATORS_TMP" >> "$CONFIG_FILE"
    
    echo "   ✅ Added GENESIS_VALIDATORS to config.yaml"
    echo "   Validators added: $(wc -l < "$GENESIS_VALIDATORS_TMP" | tr -d ' ')"
else
    echo "   ❌ Error: No genesis_validators to add - GENESIS_VALIDATORS_TMP is empty"
    echo "   This will cause zeam to fail with MissingValidatorConfig error"
    exit 1
fi

# Clean up temp file
rm -f "$GENESIS_VALIDATORS_TMP"

echo ""

# ========================================
# Generate annotated_validators.yaml with key metadata
# ========================================
echo "🔧 Generating annotated_validators.yaml..."

VALIDATORS_OUTPUT_FILE="$GENESIS_DIR/validators.yaml"
ANNOTATED_VALIDATORS_FILE="$GENESIS_DIR/annotated_validators.yaml"

if [ ! -f "$VALIDATORS_OUTPUT_FILE" ]; then
    echo "   ❌ Error: validators.yaml not found at $VALIDATORS_OUTPUT_FILE"
    exit 1
fi

ASSIGNMENT_HAS_WRAPPER=$(yq eval 'has("validators")' "$VALIDATORS_OUTPUT_FILE" 2>/dev/null)
if [ "$ASSIGNMENT_HAS_WRAPPER" != "true" ]; then
    ASSIGNMENT_HAS_WRAPPER="false"
fi

ASSIGNMENT_NODE_NAMES=()
if [ "$ASSIGNMENT_HAS_WRAPPER" = "true" ]; then
    while IFS= read -r node_name; do
        if [ -n "$node_name" ]; then
            ASSIGNMENT_NODE_NAMES+=("$node_name")
        fi
    done < <(yq eval '.validators | keys | .[]' "$VALIDATORS_OUTPUT_FILE" 2>/dev/null)
else
    while IFS= read -r node_name; do
        if [ -n "$node_name" ]; then
            ASSIGNMENT_NODE_NAMES+=("$node_name")
        fi
    done < <(yq eval 'keys | .[]' "$VALIDATORS_OUTPUT_FILE" 2>/dev/null)
fi

if [ ${#ASSIGNMENT_NODE_NAMES[@]} -eq 0 ]; then
    echo "   ❌ Error: No validator assignments found in validators.yaml"
    exit 1
fi

NODE_ASSIGNMENTS_TMP=$(mktemp)

for idx in "${!ASSIGNMENT_NODE_NAMES[@]}"; do
    node=${ASSIGNMENT_NODE_NAMES[$idx]}

    if [ "$ASSIGNMENT_HAS_WRAPPER" = "true" ]; then
        INDEX_QUERY=".validators.\"$node\"[]"
    else
        INDEX_QUERY=".\"$node\"[]"
    fi

    echo "$node:" >> "$NODE_ASSIGNMENTS_TMP"

    ENTRY_FOUND=false

    while IFS= read -r raw_index; do
        # Trim whitespace using bash parameter expansion (avoids xargs which can fail in sandboxed environments)
        raw_index="${raw_index#"${raw_index%%[![:space:]]*}"}"
        raw_index="${raw_index%"${raw_index##*[![:space:]]}"}"
        if [ -z "$raw_index" ] || [ "$raw_index" == "null" ]; then
            continue
        fi

        ENTRY_FOUND=true

        if [ "$DUAL_KEY_MODE" = true ]; then
            ATTEST_HEX_VALUE=$(yq eval ".validators[$raw_index].attester_key_pubkey_hex" "$MANIFEST_FILE" 2>/dev/null)
            PROP_HEX_VALUE=$(yq eval ".validators[$raw_index].proposer_key_pubkey_hex" "$MANIFEST_FILE" 2>/dev/null)
            if [ -z "$ATTEST_HEX_VALUE" ] || [ "$ATTEST_HEX_VALUE" == "null" ] || \
               [ -z "$PROP_HEX_VALUE" ] || [ "$PROP_HEX_VALUE" == "null" ]; then
                echo "   ❌ Error: Missing attester/proposer pubkey for validator index $raw_index in manifest"
                rm -f "$NODE_ASSIGNMENTS_TMP"
                exit 1
            fi
            ATTEST_NO_PREFIX="${ATTEST_HEX_VALUE#0x}"
            PROP_NO_PREFIX="${PROP_HEX_VALUE#0x}"
            cat << EOF >> "$NODE_ASSIGNMENTS_TMP"
  - index: $raw_index
    pubkey_hex: $ATTEST_NO_PREFIX
    privkey_file: validator_${raw_index}_attester_key_sk.ssz
  - index: $raw_index
    pubkey_hex: $PROP_NO_PREFIX
    privkey_file: validator_${raw_index}_proposer_key_sk.ssz
EOF
        else
            PUBKEY_HEX_VALUE=$(yq eval ".validators[$raw_index].$PUBKEY_FIELD" "$MANIFEST_FILE" 2>/dev/null)
            if [ -z "$PUBKEY_HEX_VALUE" ] || [ "$PUBKEY_HEX_VALUE" == "null" ]; then
                echo "   ❌ Error: Missing pubkey for validator index $raw_index in manifest"
                rm -f "$NODE_ASSIGNMENTS_TMP"
                exit 1
            fi
            PUBKEY_HEX_NO_PREFIX="${PUBKEY_HEX_VALUE#0x}"
            PRIVKEY_FILENAME="validator_${raw_index}_sk.ssz"
            cat << EOF >> "$NODE_ASSIGNMENTS_TMP"
  - index: $raw_index
    pubkey_hex: $PUBKEY_HEX_NO_PREFIX
    privkey_file: $PRIVKEY_FILENAME
EOF
        fi
    done < <(yq eval "$INDEX_QUERY" "$VALIDATORS_OUTPUT_FILE" 2>/dev/null)

    if [ "$ENTRY_FOUND" = false ]; then
        echo "  []" >> "$NODE_ASSIGNMENTS_TMP"
    fi

    if [ "$idx" -lt $(( ${#ASSIGNMENT_NODE_NAMES[@]} - 1 )) ]; then
        echo "" >> "$NODE_ASSIGNMENTS_TMP"
    fi
done

cat "$NODE_ASSIGNMENTS_TMP" > "$ANNOTATED_VALIDATORS_FILE"
rm -f "$NODE_ASSIGNMENTS_TMP"

echo "   ✅ Generated annotated_validators.yaml with pubkey and privkey metadata"

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
    if [ -f "$GENESIS_DIR/hash-sig-keys/validator_${i}_proposer_key_pk.json" ]; then
        echo "   $GENESIS_DIR/hash-sig-keys/validator_${i}_proposer_key_{pk,sk}.json"
        echo "   $GENESIS_DIR/hash-sig-keys/validator_${i}_attester_key_{pk,sk}.json"
    else
        echo "   $GENESIS_DIR/hash-sig-keys/validator_${i}_pk.json"
        echo "   $GENESIS_DIR/hash-sig-keys/validator_${i}_sk.json"
    fi
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
