#!/bin/bash
# Generate Ansible inventory from deploy-validator-config.yaml
# This script reads deploy-validator-config.yaml and generates hosts.yml for Ansible

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <deploy-validator-config.yaml> <output-hosts.yml>"
    exit 1
fi

DEPLOY_VALIDATOR_CONFIG="$1"
OUTPUT_FILE="$2"

# Check if yq is installed
if ! command -v yq &> /dev/null; then
    echo "Error: yq is required but not installed. Please install yq first."
    echo "On macOS: brew install yq"
    echo "On Linux: https://github.com/mikefarah/yq#install"
    exit 1
fi

# Check if validator config exists
if [ ! -f "$DEPLOY_VALIDATOR_CONFIG" ]; then
    echo "Error: Deploy config file not found: $DEPLOY_VALIDATOR_CONFIG"
    exit 1
fi

# Create output directory if it doesn't exist
OUTPUT_DIR=$(dirname "$OUTPUT_FILE")
mkdir -p "$OUTPUT_DIR"

# Start generating the inventory file
cat > "$OUTPUT_FILE" << 'EOF'
---
# Ansible Inventory for Lean Quickstart
# Auto-generated from deploy-validator-config.yaml
# DO NOT EDIT MANUALLY - This file is auto-generated

all:
  children:
    local:
      hosts:
        localhost:
          ansible_connection: local
          ansible_python_interpreter: auto_silent
    bootnodes:
      hosts: {}
    zeam_nodes:
      hosts: {}
    ream_nodes:
      hosts: {}
    qlean_nodes:
      hosts: {}
    lantern_nodes:
      hosts: {}
    lighthouse_nodes:
      hosts: {}
    grandine_nodes:
      hosts: {}
    ethlambda_nodes:
      hosts: {}
EOF

# Extract node information from deploy-validator-config.yaml
nodes=($(yq eval '.validators[].name' "$DEPLOY_VALIDATOR_CONFIG"))

# Process each node and generate inventory entries
for node_name in "${nodes[@]}"; do
    # Extract client type (zeam, ream, qlean, lantern, lighthouse, grandine, ethlambda)
    IFS='_' read -r -a elements <<< "$node_name"
    client_type="${elements[0]}"
    group_name="${client_type}_nodes"
    
    # Extract node-specific information
    node_ip=$(yq eval ".validators[] | select(.name == \"$node_name\") | .enrFields.ip // \"127.0.0.1\"" "$DEPLOY_VALIDATOR_CONFIG")
    node_quic=$(yq eval ".validators[] | select(.name == \"$node_name\") | .enrFields.quic // \"9000\"" "$DEPLOY_VALIDATOR_CONFIG")
    
    # Check if this is a remote deployment (IP is not localhost/127.0.0.1)
    is_remote=false
    if [[ "$node_ip" != "127.0.0.1" ]] && [[ "$node_ip" != "localhost" ]]; then
        is_remote=true
    fi
    
    # Add node to the appropriate group
    if [ "$is_remote" = true ]; then
        # Remote deployment
        yq eval -i ".all.children.$group_name.hosts.$node_name.ansible_host = \"$node_ip\"" "$OUTPUT_FILE"
        yq eval -i ".all.children.$group_name.hosts.$node_name.node_name = \"$node_name\"" "$OUTPUT_FILE"
        yq eval -i ".all.children.$group_name.hosts.$node_name.client_type = \"$client_type\"" "$OUTPUT_FILE"
        yq eval -i ".all.children.$group_name.hosts.$node_name.quic_port = $node_quic" "$OUTPUT_FILE"
    else
        # Local deployment
        yq eval -i ".all.children.$group_name.hosts.$node_name.ansible_host = \"localhost\"" "$OUTPUT_FILE"
        yq eval -i ".all.children.$group_name.hosts.$node_name.ansible_connection = \"local\"" "$OUTPUT_FILE"
        yq eval -i ".all.children.$group_name.hosts.$node_name.node_name = \"$node_name\"" "$OUTPUT_FILE"
        yq eval -i ".all.children.$group_name.hosts.$node_name.client_type = \"$client_type\"" "$OUTPUT_FILE"
        yq eval -i ".all.children.$group_name.hosts.$node_name.quic_port = $node_quic" "$OUTPUT_FILE"
    fi
done

echo "✅ Generated Ansible inventory at: $OUTPUT_FILE"
echo "   Processed ${#nodes[@]} node(s): ${nodes[*]}"

