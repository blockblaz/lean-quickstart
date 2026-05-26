#!/bin/bash
set -e

# generate-shadow-yaml.sh — Generate shadow.yaml from validator-config.yaml
#
# Multi-client: reuses existing client-cmds/<client>-cmd.sh to get node_binary.
# Works for zeam, ream, lantern, gean, or any client with a *-cmd.sh file.
#
# Usage:
#   ./generate-shadow-yaml.sh <genesis-dir> --project-root <path> [--stop-time 360s] [--output shadow.yaml]
#       [--seed <int>] [--shadow-data-dir <path>] [--topology-gml <path>] [--bandwidths-json <path>]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

show_usage() {
    cat << EOF
Usage: $0 <genesis-dir> --project-root <path> [--stop-time 360s] [--output shadow.yaml]
       [--seed <int>] [--shadow-data-dir <path>] [--topology-gml <path>] [--bandwidths-json <path>]

Generate a Shadow network simulator configuration (shadow.yaml) from validator-config.yaml.

Arguments:
  genesis-dir          Path to genesis directory containing validator-config.yaml

Options:
  --project-root <path>    Project root directory (parent of lean-quickstart). Required.
  --stop-time <time>       Shadow simulation stop time (default: 360s)
  --output <path>          Output shadow.yaml path (default: <project-root>/shadow.yaml)
  --seed <int>             Shadow general.seed for reproducibility
  --shadow-data-dir <path> Shadow data output directory (default: <project-root>/shadow.data)
  --topology-gml <path>    GML topology file; enables geo-latency graph mode
  --bandwidths-json <path> JSON file mapping node_N → bandwidth tier

This script is client-agnostic. It reads node names from validator-config.yaml,
extracts the client name from the node prefix (e.g., zeam_0 → zeam), and sources
the corresponding client-cmds/<client>-cmd.sh to generate per-node arguments.
EOF
    exit 1
}

# ========================================
# Parse arguments
# ========================================
if [ -z "$1" ] || [ "${1:0:1}" == "-" ]; then
    show_usage
fi

GENESIS_DIR="$(cd "$1" && pwd)"
shift

PROJECT_ROOT=""
STOP_TIME="360s"
OUTPUT_FILE=""
SEED=""
SHADOW_DATA_DIR=""
TOPOLOGY_GML=""
BANDWIDTHS_JSON=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-root)
            if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                PROJECT_ROOT="$(cd "$2" && pwd)"
                shift 2
            else
                echo "❌ Error: --project-root requires a path"
                exit 1
            fi
            ;;
        --stop-time)
            if [ -n "$2" ]; then
                STOP_TIME="$2"
                shift 2
            else
                echo "❌ Error: --stop-time requires a value"
                exit 1
            fi
            ;;
        --output)
            if [ -n "$2" ]; then
                OUTPUT_FILE="$2"
                shift 2
            else
                echo "❌ Error: --output requires a path"
                exit 1
            fi
            ;;
        --seed)
            if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                SEED="$2"
                shift 2
            else
                echo "❌ Error: --seed requires an integer"
                exit 1
            fi
            ;;
        --shadow-data-dir)
            if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                mkdir -p "$2"
                SHADOW_DATA_DIR="$(cd "$2" && pwd)"
                shift 2
            else
                echo "❌ Error: --shadow-data-dir requires a path"
                exit 1
            fi
            ;;
        --topology-gml)
            if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                TOPOLOGY_GML="$2"
                shift 2
            else
                echo "❌ Error: --topology-gml requires a path"
                exit 1
            fi
            ;;
        --bandwidths-json)
            if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                BANDWIDTHS_JSON="$2"
                shift 2
            else
                echo "❌ Error: --bandwidths-json requires a path"
                exit 1
            fi
            ;;
        *)
            echo "❌ Unknown option: $1"
            show_usage
            ;; 
    esac
done

if [ -z "$PROJECT_ROOT" ]; then
    echo "❌ Error: --project-root is required"
    show_usage
fi

if [ -z "$OUTPUT_FILE" ]; then
    OUTPUT_FILE="$PROJECT_ROOT/shadow.yaml"
fi

VALIDATOR_CONFIG="$GENESIS_DIR/validator-config.yaml"
if [ ! -f "$VALIDATOR_CONFIG" ]; then
    echo "❌ Error: validator-config.yaml not found at $VALIDATOR_CONFIG"
    exit 1
fi

# ========================================
# Read nodes from validator-config.yaml
# ========================================
node_names=($(yq eval '.validators[].name' "$VALIDATOR_CONFIG"))
node_count=${#node_names[@]}

if [ "$node_count" -eq 0 ]; then
    echo "❌ Error: No validators found in $VALIDATOR_CONFIG"
    exit 1
fi

echo "🔧 Generating shadow.yaml for $node_count nodes..."

# ========================================
# Write shadow.yaml preamble
# ========================================
USE_GML=false
if [ -n "$TOPOLOGY_GML" ] && [ -f "$TOPOLOGY_GML" ]; then
    USE_GML=true
    echo "   Using GML topology: $TOPOLOGY_GML"
fi

if [ -n "$BANDWIDTHS_JSON" ] && [ -f "$BANDWIDTHS_JSON" ]; then
    echo "   Using bandwidth tiers: $BANDWIDTHS_JSON"
fi

cat > "$OUTPUT_FILE" << EOF
# Auto-generated Shadow network simulator configuration
# Generated from: $VALIDATOR_CONFIG
# Nodes: ${node_names[*]}

general:
  model_unblocked_syscall_latency: true
  stop_time: $STOP_TIME
EOF

if [ -n "$SEED" ]; then
    echo "  seed: $SEED" >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" << EOF

experimental:
  native_preemption_enabled: true

network:
  graph:
EOF

if $USE_GML; then
    cat >> "$OUTPUT_FILE" << EOF
    type: gml
    file:
      path: $TOPOLOGY_GML
  use_shortest_path: true
EOF
else
    cat >> "$OUTPUT_FILE" << EOF
    type: 1_gbit_switch
EOF
fi

cat >> "$OUTPUT_FILE" << EOF

hosts:
EOF

# ========================================
# Generate per-node host entries
# ========================================
for i in "${!node_names[@]}"; do
    item="${node_names[$i]}"

    # Extract client name from node prefix (zeam_0 → zeam, leanspec_0 → leanspec)
    IFS='_' read -r -a elements <<< "$item"
    client="${elements[0]}"

    # DNS-valid hostname: underscores → hyphens (Shadow requirement)
    hostname="${item//_/-}"

    # Extract IP from validator-config
    ip=$(yq eval ".validators[$i].enrFields.ip" "$VALIDATOR_CONFIG")

    # Set up environment for parse-vc.sh and client-cmd.sh
    # These scripts expect: $item, $configDir, $dataDir, $scriptDir, $validatorConfig
    export scriptDir="$SCRIPT_DIR"
    export configDir="$GENESIS_DIR"
    export dataDir="${SHADOW_DATA_DIR:-$PROJECT_ROOT/shadow.data}/hosts/$hostname"
    export validatorConfig="$GENESIS_DIR"

    # Source parse-vc.sh to extract per-node config (quicPort, metricsPort, apiPort, etc.)
    # parse-vc.sh uses $item and $configDir
    source "$SCRIPT_DIR/parse-vc.sh"

    # Source client-cmd.sh to get node_binary
    node_setup="binary"
    client_cmd="$SCRIPT_DIR/client-cmds/${client}-cmd.sh"
    if [ ! -f "$client_cmd" ]; then
        echo "❌ Error: Client command script not found: $client_cmd"
        echo "   Available clients:"
        ls "$SCRIPT_DIR/client-cmds/"*-cmd.sh 2>/dev/null | sed 's/.*\//  /' | sed 's/-cmd.sh//'
        exit 1
    fi
    source "$client_cmd"

    # node_binary is now set by the client-cmd.sh script
    # Convert relative paths to absolute paths for Shadow
    # Extract the binary path (first word) and args (rest)
    binary_path=$(echo "$node_binary" | awk '{print $1}')
    binary_args=$(echo "$node_binary" | sed "s|^[^ ]*||")

    # Make binary path absolute
    if [[ "$binary_path" != /* ]]; then
        binary_path="$(cd "$(dirname "$binary_path")" 2>/dev/null && pwd)/$(basename "$binary_path")" 2>/dev/null || binary_path="$PROJECT_ROOT/${binary_path#./}"
    fi

    # Make all path args absolute: replace $configDir, $dataDir references with absolute paths
    # The client-cmd.sh already uses $configDir and $dataDir which we set to absolute paths

    # Determine bandwidth tier from bandwidths JSON if available
    if [ -n "$BANDWIDTHS_JSON" ] && [ -f "$BANDWIDTHS_JSON" ]; then
        BW=$(python3 -c "
import json, sys
with open('$BANDWIDTHS_JSON') as f:
    bw = json.load(f)
print(bw.get('node_$i', '50 Mbit'))
" 2>/dev/null)
    else
        BW=""
    fi

    # Determine network_node_id
    if $USE_GML; then
        NET_NODE_ID=$i
    else
        NET_NODE_ID=0
    fi

    # Write host entry
    cat >> "$OUTPUT_FILE" << EOF
  $hostname:
    network_node_id: $NET_NODE_ID
    ip_addr: $ip
EOF

    if [ -n "$BW" ]; then
        cat >> "$OUTPUT_FILE" << EOF
    bandwidth_up: "$BW"
    bandwidth_down: "$BW"
EOF
    fi

    cat >> "$OUTPUT_FILE" << EOF
    processes:
    - path: $binary_path
      args: >-
       $binary_args
      start_time: 1s
      expected_final_state: running

EOF

    echo "   ✅ $item → $hostname ($ip) [$client]"
done

echo ""
echo "📄 Shadow config written to: $OUTPUT_FILE"
echo "   Stop time: $STOP_TIME"
echo "   Nodes: $node_count"
