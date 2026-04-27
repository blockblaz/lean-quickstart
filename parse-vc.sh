#!/bin/bash

# parse validator-config to load values related to the $item
# needed for ream and qlean (or any other client), zeam picks directly from validator-config
# 1. load quic port and export it in $quicPort
# 2. private key and dump it into a file $client.key and export it in $privKeyPath
# 3. devnet and export it in $devnet

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

# Automatically extract HTTP port using yq (optional - only some clients use it)
httpPort=$(yq eval ".validators[] | select(.name == \"$item\") | .httpPort" "$validator_config_file")
if [ -z "$httpPort" ] || [ "$httpPort" == "null" ]; then
    httpPort=""
fi

# Automatically extract API port using yq (optional - only some clients use it)
apiPort=$(yq eval ".validators[] | select(.name == \"$item\") | .apiPort" "$validator_config_file")
if [ -z "$apiPort" ] || [ "$apiPort" == "null" ]; then
    apiPort=""
fi

# Automatically extract devnet using yq (optional - only ream uses it)
devnet=$(yq eval ".validators[] | select(.name == \"$item\") | .devnet" "$validator_config_file")
if [ -z "$devnet" ] || [ "$devnet" == "null" ]; then
    devnet=""
fi

# Automatically extract isAggregator flag using yq (defaults to false if not set)
isAggregator=$(yq eval ".validators[] | select(.name == \"$item\") | .isAggregator // false" "$validator_config_file")
if [ -z "$isAggregator" ] || [ "$isAggregator" == "null" ]; then
    isAggregator="false"
fi

# Compute the full set of unique subnet ids as a CSV (e.g. "0,1"). Aggregators
# in multi-subnet deployments must subscribe to every subnet's attestation
# topic to aggregate votes across committees. Client-cmd scripts pass this
# along as --aggregate-subnet-ids when the node is an aggregator and the
# network has more than one subnet.
aggregateSubnetIds=$(yq eval '[.validators[].subnet // 0] | unique | sort | join(",")' "$validator_config_file")
if [ -z "$aggregateSubnetIds" ] || [ "$aggregateSubnetIds" == "null" ]; then
    aggregateSubnetIds=""
fi
export aggregateSubnetIds

# Extract attestation_committee_count from config section (optional - only if explicitly set)
attestationCommitteeCount=$(yq eval ".config.attestation_committee_count" "$validator_config_file")
if [ -z "$attestationCommitteeCount" ] || [ "$attestationCommitteeCount" == "null" ]; then
    attestationCommitteeCount=""
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

# Extract hash-sig key configuration from top-level config
keyType=$(yq eval ".config.keyType" "$validator_config_file")
hashSigKeyIndex=$(yq eval ".validators | to_entries | .[] | select(.value.name == \"$item\") | .key" "$validator_config_file")

# Load hash-sig keys if configured
if [ "$keyType" == "hash-sig" ] && [ "$hashSigKeyIndex" != "null" ] && [ -n "$hashSigKeyIndex" ]; then
    # devnet4+: separate proposer + attester keys (hash-sig-cli); legacy: single pk/sk per index
    _proposer_pk="$configDir/hash-sig-keys/validator_${hashSigKeyIndex}_proposer_key_pk.json"
    _proposer_sk="$configDir/hash-sig-keys/validator_${hashSigKeyIndex}_proposer_key_sk.json"
    _attester_pk="$configDir/hash-sig-keys/validator_${hashSigKeyIndex}_attester_key_pk.json"
    _attester_sk="$configDir/hash-sig-keys/validator_${hashSigKeyIndex}_attester_key_sk.json"
    _legacy_pk="$configDir/hash-sig-keys/validator_${hashSigKeyIndex}_pk.json"
    _legacy_sk="$configDir/hash-sig-keys/validator_${hashSigKeyIndex}_sk.json"

    if [ -f "$_proposer_pk" ] && [ -f "$_attester_pk" ]; then
        hashSigPkPath="$_proposer_pk"
        hashSigSkPath="$_proposer_sk"
        export HASH_SIG_PROPOSER_PK_PATH="$_proposer_pk"
        export HASH_SIG_PROPOSER_SK_PATH="$_proposer_sk"
        export HASH_SIG_ATTESTER_PK_PATH="$_attester_pk"
        export HASH_SIG_ATTESTER_SK_PATH="$_attester_sk"
        if [ ! -f "$hashSigSkPath" ] || [ ! -f "$_attester_sk" ]; then
            echo "Warning: Hash-sig secret key(s) missing for dual-key layout (validator_${hashSigKeyIndex})"
            echo "Run genesis generator: ./generate-genesis.sh $configDir"
        fi
    else
        hashSigPkPath="$_legacy_pk"
        hashSigSkPath="$_legacy_sk"
        if [ ! -f "$hashSigPkPath" ]; then
            echo "Warning: Hash-sig public key not found at $hashSigPkPath"
            echo "Run genesis generator to create hash-sig keys: ./generate-genesis.sh $configDir"
        fi
        if [ ! -f "$hashSigSkPath" ]; then
            echo "Warning: Hash-sig secret key not found at $hashSigSkPath"
            echo "Run genesis generator to create hash-sig keys: ./generate-genesis.sh $configDir"
        fi
    fi

    # Export hash-sig key paths for client use (HASH_SIG_PK_PATH = proposer when dual-key)
    export HASH_SIG_PK_PATH="$hashSigPkPath"
    export HASH_SIG_SK_PATH="$hashSigSkPath"
    export HASH_SIG_KEY_INDEX="$hashSigKeyIndex"
    
    echo "Node: $item"
    echo "QUIC Port: $quicPort"
    echo "Metrics Port: $metricsPort"
    echo "API Port: ${apiPort:-<not set>}"
    echo "Devnet: ${devnet:-<not set>}"
    echo "Private Key File: $privKeyPath"
    echo "Key Type: $keyType"
    echo "Hash-Sig Key Index: $hashSigKeyIndex"
    echo "Hash-Sig Public Key: $hashSigPkPath"
    echo "Hash-Sig Secret Key: $hashSigSkPath"
    if [ -n "${HASH_SIG_ATTESTER_PK_PATH:-}" ]; then
        echo "Hash-Sig Attester PK: $HASH_SIG_ATTESTER_PK_PATH"
        echo "Hash-Sig Attester SK: $HASH_SIG_ATTESTER_SK_PATH"
    fi
    echo "Is Aggregator: $isAggregator"
    if [ -n "$attestationCommitteeCount" ]; then
        echo "Attestation Committee Count: $attestationCommitteeCount"
    fi
else
    echo "Node: $item"
    echo "QUIC Port: $quicPort"
    echo "Metrics Port: $metricsPort"
    echo "API Port: ${apiPort:-<not set>}"
    echo "Devnet: ${devnet:-<not set>}"
    echo "Private Key File: $privKeyPath"
    echo "Is Aggregator: $isAggregator"
    if [ -n "$attestationCommitteeCount" ]; then
        echo "Attestation Committee Count: $attestationCommitteeCount"
    fi
fi
