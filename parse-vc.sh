#!/bin/bash

# parse deploy-validator-config.yaml to load values related to the $item
# needed for ream and qlean (or any other client), zeam picks directly from config
# 1. load quic port and export it in $quicPort
# 2. private key and dump it into a file $client.key and export it in $privKeyPath
# 3. devnet and export it in $devnet
# 4. docker image (already merged in deploy-validator-config.yaml)

# $item, $configDir (genesis dir) is available here
# Note: deploy-validator-config.yaml already has user overrides merged (from merge-config.sh)

# Check if yq is installed
if ! command -v yq &> /dev/null; then
    echo "Error: yq is required but not installed. Please install yq first."
    echo "On macOS: brew install yq"
    echo "On Linux: https://github.com/mikefarah/yq#install"
    exit 1
fi

# Use deploy-validator-config.yaml (has user overrides merged)
deploy_validator_config_file="$configDir/deploy-validator-config.yaml"
if [ ! -f "$deploy_validator_config_file" ]; then
    echo "Error: deploy-validator-config.yaml not found at $deploy_validator_config_file"
    echo "This file should have been created by merge-config.sh"
    exit 1
fi

# Automatically extract QUIC port using yq
quicPort=$(yq eval ".validators[] | select(.name == \"$item\") | .enrFields.quic" "$deploy_validator_config_file")

# Validate that we found a QUIC port for this node
if [ -z "$quicPort" ] || [ "$quicPort" == "null" ]; then
    echo "Error: No QUIC port found for node '$item' in $deploy_validator_config_file"
    echo "Available nodes:"
    yq eval '.validators[].name' "$deploy_validator_config_file"
    exit 1
fi

# Automatically extract metrics port using yq
metricsPort=$(yq eval ".validators[] | select(.name == \"$item\") | .metricsPort" "$deploy_validator_config_file")

# Validate that we found a metrics port for this node
if [ -z "$metricsPort" ] || [ "$metricsPort" == "null" ]; then
    echo "Error: No metrics port found for node '$item' in $deploy_validator_config_file"
    echo "Available nodes:"
    yq eval '.validators[].name' "$deploy_validator_config_file"
    exit 1
fi

# Automatically extract devnet using yq (optional - only ream uses it)
devnet=$(yq eval ".validators[] | select(.name == \"$item\") | .devnet" "$deploy_validator_config_file")
if [ -z "$devnet" ] || [ "$devnet" == "null" ]; then
    devnet=""
fi

# Automatically extract private key using yq
privKey=$(yq eval ".validators[] | select(.name == \"$item\") | .privkey" "$deploy_validator_config_file")

# Validate that we found a private key for this node
if [ -z "$privKey" ] || [ "$privKey" == "null" ]; then
    echo "Error: No private key found for node '$item' in $deploy_validator_config_file"
    exit 1
fi

# Create the private key file
privKeyPath="$item.key"
echo "$privKey" > "$configDir/$privKeyPath"

# Extract hash-sig key configuration from top-level config
keyType=$(yq eval ".config.keyType" "$deploy_validator_config_file")
hashSigKeyIndex=$(yq eval ".validators | to_entries | .[] | select(.value.name == \"$item\") | .key" "$deploy_validator_config_file")

# Load hash-sig keys if configured
if [ "$keyType" == "hash-sig" ] && [ "$hashSigKeyIndex" != "null" ] && [ -n "$hashSigKeyIndex" ]; then
    # Set hash-sig key paths
    hashSigPkPath="$configDir/hash-sig-keys/validator_${hashSigKeyIndex}_pk.json"
    hashSigSkPath="$configDir/hash-sig-keys/validator_${hashSigKeyIndex}_sk.json"

    # Validate that hash-sig keys exist
    if [ ! -f "$hashSigPkPath" ]; then
        echo "Warning: Hash-sig public key not found at $hashSigPkPath"
        echo "Run genesis generator to create hash-sig keys: ./generate-genesis.sh $configDir"
    fi

    if [ ! -f "$hashSigSkPath" ]; then
        echo "Warning: Hash-sig secret key not found at $hashSigSkPath"
        echo "Run genesis generator to create hash-sig keys: ./generate-genesis.sh $configDir"
    fi

    # Export hash-sig key paths for client use
    export HASH_SIG_PK_PATH="$hashSigPkPath"
    export HASH_SIG_SK_PATH="$hashSigSkPath"
    export HASH_SIG_KEY_INDEX="$hashSigKeyIndex"
fi

# Load docker image for this node (already merged in deploy-validator-config.yaml)
docker_image=$(yq eval ".validators[] | select(.name == \"$item\") | .image" "$deploy_validator_config_file" 2>/dev/null)
if [ -z "$docker_image" ] || [ "$docker_image" == "null" ]; then
    echo "Warning: No docker image found for $item"
    docker_image=""
fi

echo "Node: $item"
echo "Docker Image: ${docker_image:-<not set>}"
echo "QUIC Port: $quicPort"
echo "Metrics Port: $metricsPort"
echo "Devnet: ${devnet:-<not set>}"
echo "Private Key File: $privKeyPath"
if [ "$keyType" == "hash-sig" ] && [ "$hashSigKeyIndex" != "null" ] && [ -n "$hashSigKeyIndex" ]; then
    echo "Key Type: $keyType"
    echo "Hash-Sig Key Index: $hashSigKeyIndex"
    echo "Hash-Sig Public Key: $hashSigPkPath"
    echo "Hash-Sig Secret Key: $hashSigSkPath"
fi
