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

# Check if this validator uses hash-sig keys
keyType=$(yq eval ".validators[] | select(.name == \"$item\") | .keyType" "$validator_config_file")

if [ "$keyType" == "hash-sig" ]; then
    echo "🔐 Validator uses hash-based signatures (post-quantum secure)"
    
    # Extract the hash-sig key index
    hashSigKeyIndex=$(yq eval ".validators[] | select(.name == \"$item\") | .hashSigKeyIndex" "$validator_config_file")
    
    if [ -z "$hashSigKeyIndex" ] || [ "$hashSigKeyIndex" == "null" ]; then
        echo "Error: hash-sig keyType specified but no hashSigKeyIndex found for node '$item'"
        exit 1
    fi
    
    # Set paths to hash-sig keys
    hashSigKeysDir="$configDir/hash-sig-keys"
    hashSigPubKeyPath="$hashSigKeysDir/validator_${hashSigKeyIndex}_pk.json"
    hashSigSecKeyPath="$hashSigKeysDir/validator_${hashSigKeyIndex}_sk.json"
    
    # Validate that the key files exist
    if [ ! -f "$hashSigPubKeyPath" ]; then
        echo "Error: Hash-sig public key not found at $hashSigPubKeyPath"
        echo "Run generate-genesis.sh to generate hash-sig keys first"
        exit 1
    fi
    
    if [ ! -f "$hashSigSecKeyPath" ]; then
        echo "Error: Hash-sig secret key not found at $hashSigSecKeyPath"
        echo "Run generate-genesis.sh to generate hash-sig keys first"
        exit 1
    fi
    
    # Export hash-sig key paths as environment variables for the client
    export HASH_SIG_PUBLIC_KEY="$hashSigPubKeyPath"
    export HASH_SIG_SECRET_KEY="$hashSigSecKeyPath"
    export HASH_SIG_KEY_INDEX="$hashSigKeyIndex"
    
    echo "Hash-Sig Key Index: $hashSigKeyIndex"
    echo "Hash-Sig Public Key: $hashSigPubKeyPath"
    echo "Hash-Sig Secret Key: $hashSigSecKeyPath"
else
    echo "Using standard cryptography (not post-quantum secure)"
fi

echo "Node: $item"
echo "QUIC Port: $quicPort"
echo "Metrics Port: $metricsPort"
echo "Private Key File: $privKeyPath"
