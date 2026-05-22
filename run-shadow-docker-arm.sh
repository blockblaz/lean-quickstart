#!/bin/bash
set -e

# run-shadow.sh — One-command Shadow multi-node devnet test
#
# Multi-client: auto-detects client types from validator-config.yaml node names.
# Works for zeam, ream, lantern, or any client with a client-cmds/<client>-cmd.sh.
#
# Usage:
#   ./lean-quickstart/run-shadow.sh [--stop-time 60s] [--genesis-dir <path>] [--forceKeyGen]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Shadow virtual clock epoch: Jan 1, 2000 00:00:00 UTC = 946684800
# Genesis time = epoch + 30s warmup = 946684830
SHADOW_GENESIS_TIME=946684830

show_usage() {
    cat << EOF
Usage: $0 [--stop-time 60s] [--genesis-dir <path>] [--forceKeyGen]

Run a Shadow multi-node devnet test. Generates genesis, builds shadow.yaml, and runs Shadow.

Options:
  --stop-time <time>     Shadow simulation stop time (default: 60s)
  --genesis-dir <path>   Genesis directory (default: <script-dir>/shadow-devnet/genesis)
  --forceKeyGen          Force regeneration of hash-sig validator keys

Environment:
  Shadow's virtual clock starts at Unix 946684800 (Jan 1, 2000).
  Genesis time is fixed at 946684860 (epoch + 60s warmup).

Examples:
  ./lean-quickstart/run-shadow.sh
  ./lean-quickstart/run-shadow.sh --stop-time 600s --forceKeyGen
EOF
    exit 1
}

# ========================================
# Parse arguments
# ========================================
STOP_TIME="60s"
GENESIS_DIR="$SCRIPT_DIR/shadow-devnet/genesis"
FORCE_KEYGEN=""
SHADOW_DATA_DIR="${SHADOW_DATA_DIR:-/tmp/shadow.data}"
export SHADOW_DATA_DIR

while [[ $# -gt 0 ]]; do
    case "$1" in
        --stop-time)
            STOP_TIME="$2"
            shift 2
            ;;
        --genesis-dir)
            GENESIS_DIR="$(cd "$2" && pwd)"
            shift 2
            ;;
        --forceKeyGen)
            FORCE_KEYGEN="--forceKeyGen"
            shift
            ;;
        --help|-h)
            show_usage
            ;;
        *)
            echo "❌ Unknown option: $1"
            show_usage
            ;;
    esac
done

# ========================================
# Validate dependencies
# ========================================
echo "🔍 Checking dependencies..."

missing_deps=()
for dep in yq docker; do
    if ! command -v "$dep" &> /dev/null; then
        missing_deps+=("$dep")
    fi
done

if [ ${#missing_deps[@]} -gt 0 ]; then
    echo "❌ Missing required tools: ${missing_deps[*]}"
    echo ""
    echo "Install instructions:"
    for dep in "${missing_deps[@]}"; do
        case "$dep" in
            yq)     echo "  yq: brew install yq (macOS) or https://github.com/mikefarah/yq#install" ;;
            docker) echo "  docker: https://docs.docker.com/get-docker/" ;;
        esac
    done
    exit 1
fi
echo "   ✅ All dependencies found"

# ========================================
# Validate genesis directory
# ========================================
VALIDATOR_CONFIG="$GENESIS_DIR/validator-config.yaml"
if [ ! -f "$VALIDATOR_CONFIG" ]; then
    echo "❌ Error: validator-config.yaml not found at $VALIDATOR_CONFIG"
    echo "   Use --genesis-dir to specify a genesis directory with validator-config.yaml"
    exit 1
fi

# Auto-detect if we need to regenerate keys
expected_validator_count=$(yq eval '.validators[].count' "$VALIDATOR_CONFIG" | awk '{sum+=$1} END {print sum}')
manifest_file="$GENESIS_DIR/hash-sig-keys/validator-keys-manifest.yaml"
if [ -f "$manifest_file" ]; then
    manifest_key_count=$(grep -c 'pubkey_hex' "$manifest_file" || echo 0)
    expected_manifest_keys=$((expected_validator_count * 2))
    if [ "$manifest_key_count" -ne "$expected_manifest_keys" ]; then
        echo "   ⚠️  Validator count changed. Automatically forcing key regeneration..."
        FORCE_KEYGEN="--forceKeyGen"
    fi
else
    echo "   ℹ️  No validator keys found. Automatically forcing key generation..."
    FORCE_KEYGEN="--forceKeyGen"
fi

# Auto-detect clients from node name prefixes
clients=($(yq eval '.validators[].name' "$VALIDATOR_CONFIG" | sed 's/_[0-9]*$//' | sort -u))
echo "   Detected clients: ${clients[*]}"

# Verify client-cmd.sh exists for each client
for client in "${clients[@]}"; do
    client_cmd="$SCRIPT_DIR/client-cmds/${client}-cmd.sh"
    if [ ! -f "$client_cmd" ]; then
        echo "❌ Error: No client-cmd script for '$client': $client_cmd"
        exit 1
    fi
done

# ========================================
# Step 1: Generate genesis
# ========================================
echo ""
echo "📦 Step 1: Generating genesis (genesis-time=$SHADOW_GENESIS_TIME)..."
"$SCRIPT_DIR/generate-genesis.sh" "$GENESIS_DIR" --genesis-time "$SHADOW_GENESIS_TIME" $FORCE_KEYGEN

# ========================================
# Step 2: Generate shadow.yaml
# ========================================
echo ""
echo "📄 Step 2: Generating shadow.yaml..."
SHADOW_YAML="$PROJECT_ROOT/shadow.yaml"
"$SCRIPT_DIR/generate-shadow-yaml.sh" "$GENESIS_DIR" \
    --project-root "$PROJECT_ROOT" \
    --stop-time "$STOP_TIME" \
    --output "$SHADOW_YAML"

# ========================================
# Step 3: Run Shadow
# ========================================
echo ""
echo "🚀 Step 3: Running Shadow simulation..."
echo "   Config: $SHADOW_YAML"
echo "   Stop time: $STOP_TIME"

# Clean previous Shadow data (ensures a 100% fresh database and network on every run)
rm -rf "$SHADOW_DATA_DIR"
rm -rf "$PROJECT_ROOT/shadow.data"

# Run Shadow inside Docker from project root (since paths in shadow.yaml are relative/absolute to the workspace)
docker run --rm --name shadow-sim-container \
    --platform linux/arm64 \
    --security-opt seccomp=unconfined \
    --shm-size 4g \
    -v "$PROJECT_ROOT:$PROJECT_ROOT" \
    -v "/tmp:/tmp" \
    -w "$PROJECT_ROOT" \
    --entrypoint /bin/bash \
    kamilsa/shadow-arm:latest \
    -c "shadow -d $SHADOW_DATA_DIR $SHADOW_YAML" &
SIM_PID=$!

# Wait for the simulation process to finish
wait $SIM_PID

# ========================================
# Print results
# ========================================
echo ""
echo "✅ Shadow simulation complete!"
echo ""
echo "📂 Log locations:"
for log in "$SHADOW_DATA_DIR"/hosts/*/*.stderr; do
    if [ -f "$log" ]; then
        echo "   $log"
    fi
done
echo ""
echo "To check consensus:"
echo "   grep 'Latest Finalized:' /tmp/shadow.data/hosts/*/zeam.1000.stderr"
