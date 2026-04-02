#!/bin/bash
set -e

# run-shadow.sh — One-command Shadow multi-node devnet test
#
# Multi-client: auto-detects client types from validator-config.yaml node names.
# Works for zeam, ream, lantern, or any client with a client-cmds/<client>-cmd.sh.
#
# Usage:
#   ./lean-quickstart/run-shadow.sh [--stop-time 360s] [--genesis-dir <path>] [--forceKeyGen]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Shadow virtual clock epoch: Jan 1, 2000 00:00:00 UTC = 946684800
# Genesis time = epoch + 60s warmup = 946684860
SHADOW_GENESIS_TIME=946684860

show_usage() {
    cat << EOF
Usage: $0 [--stop-time 360s] [--genesis-dir <path>] [--forceKeyGen]

Run a Shadow multi-node devnet test. Generates genesis, builds shadow.yaml, and runs Shadow.

Options:
  --stop-time <time>     Shadow simulation stop time (default: 360s)
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
STOP_TIME="360s"
GENESIS_DIR="$SCRIPT_DIR/shadow-devnet/genesis"
FORCE_KEYGEN=""

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
for dep in shadow yq docker; do
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
            shadow) echo "  shadow: https://shadow.github.io/docs/guide/install.html" ;;
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

# Clean previous Shadow data
rm -rf "$PROJECT_ROOT/shadow.data"

# Run Shadow from project root (since paths in shadow.yaml may be relative)
cd "$PROJECT_ROOT"
shadow "$SHADOW_YAML"

# ========================================
# Print results
# ========================================
echo ""
echo "✅ Shadow simulation complete!"
echo ""
echo "📂 Log locations:"
for log in "$PROJECT_ROOT"/shadow.data/hosts/*/*.stderr; do
    if [ -f "$log" ]; then
        echo "   $log"
    fi
done
echo ""
echo "To check consensus:"
echo "   grep 'new_head\\|finalized' shadow.data/hosts/*/*.stderr | tail -20"
