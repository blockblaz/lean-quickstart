#!/bin/bash

#-----------------------lantern setup----------------------
# Platform-specific lantern image
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    LANTERN_IMAGE="piertwo/lantern:v0.0.3-test-amd64"
elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    LANTERN_IMAGE="piertwo/lantern:v0.0.3-test-arm64"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

devnet_flag=""
if [ -n "$devnet" ]; then
        devnet_flag="--devnet $devnet"
fi

# Lantern does not support --is-aggregator flag (unlike zeam)
# The aggregator role is determined by the validator-config.yaml isAggregator field
# which lantern reads directly from the config file
aggregator_flag=""

# Set attestation committee count flag if explicitly configured
attestation_committee_flag=""
if [ -n "$attestationCommitteeCount" ]; then
    attestation_committee_flag="--attestation-committee-count $attestationCommitteeCount"
fi

# Set HTTP port (default to 5055 if not specified in validator-config.yaml)
if [ -z "$httpPort" ]; then
    httpPort="5055"
fi

# Lantern's repo: https://github.com/Pier-Two/lantern
node_binary="$scriptDir/lantern/build/lantern_cli \
        --data-dir $dataDir/$item \
        --genesis-config $configDir/config.yaml \
        --validator-registry-path $configDir/validators.yaml \
        --genesis-state $configDir/genesis.ssz \
        --validator-config $configDir/validator-config.yaml \
        $devnet_flag \
        --nodes-path $configDir/nodes.yaml \
        --node-id $item --node-key-path $configDir/$privKeyPath \
        --listen-address /ip4/0.0.0.0/udp/$quicPort/quic-v1 \
        --metrics-port $metricsPort \
        --http-port $httpPort \
        --log-level debug \
        --hash-sig-key-dir $configDir/hash-sig-keys \
        $attestation_committee_flag"

node_docker="$LANTERN_IMAGE --data-dir /data \
        --genesis-config /config/config.yaml \
        --validator-registry-path /config/validators.yaml \
        --genesis-state /config/genesis.ssz \
        --validator-config /config/validator-config.yaml \
        $devnet_flag \
        --nodes-path /config/nodes.yaml \
        --node-id $item --node-key-path /config/$privKeyPath \
        --listen-address /ip4/0.0.0.0/udp/$quicPort/quic-v1 \
        --metrics-port $metricsPort \
        --http-port $httpPort \
        --log-level debug \
        --hash-sig-key-dir /config/hash-sig-keys \
        $attestation_committee_flag"

# choose either binary or docker
node_setup="docker"
