#!/bin/bash

# parse validator-config to load values related to the $item
# needed for ream and qlean (or any other client), zeam picks directly from validator-config
# 1. load quic port and export it in $quicPort
# 2. private key and dump it into a file $client.key and export it in $privKeyPath

# $item, $configDir (genesis dir) is available here

# Check if yq is installed
if ! command -v yq &> /dev/null; then
    echo "Error: yq is required but not installed. Please install yq first."
    echo "On macOS: brew install yq"
    echo "On Linux: https://github.com/mikefarah/yq#install"
    exit 1
fi

# Validate that validator config file exists
validator_config_file="$configDir/validator-config.yaml"
if [ ! -f "$validator_config_file" ]; then
    echo "Error: Validator config file not found at $validator_config_file"
    exit 1
fi

# Automatically extract QUIC port using yq
quicPort=$(yq eval ".validators[] | select(.name == \"$item\") | .enrFields.quic" "$validator_config_file")

# Validate that we found a QUIC port for this node
if [ -z "$quicPort" ] || [ "$quicPort" == "null" ]; then
    echo "Error: No QUIC port found for node '$item' in $validator_config_file"
    echo "Available nodes:"
    yq eval '.validators[].name' "$validator_config_file"
    exit 1
fi

# Automatically extract metrics port using yq
metricsPort=$(yq eval ".validators[] | select(.name == \"$item\") | .metricsPort" "$validator_config_file")

# Validate that we found a metrics port for this node
if [ -z "$metricsPort" ] || [ "$metricsPort" == "null" ]; then
    echo "Error: No metrics port found for node '$item' in $validator_config_file"
    echo "Available nodes:"
    yq eval '.validators[].name' "$validator_config_file"
    exit 1
fi

# Automatically extract private key using yq
privKey=$(yq eval ".validators[] | select(.name == \"$item\") | .privkey" "$validator_config_file")

# Validate that we found a private key for this node
if [ -z "$privKey" ] || [ "$privKey" == "null" ]; then
    echo "Error: No private key found for node '$item' in $validator_config_file"
    exit 1
fi

# Create the private key file
privKeyPath="$item.key"
echo "$privKey" > "$configDir/$privKeyPath"

echo "Node: $item"
echo "QUIC Port: $quicPort"
echo "Metrics Port: $metricsPort"
echo "Private Key File: $privKeyPath"
