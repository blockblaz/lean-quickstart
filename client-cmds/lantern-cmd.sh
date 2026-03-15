#!/bin/bash

#-----------------------lantern setup----------------------
if [ -z "$docker_image" ]; then
    docker_image="piertwo/lantern:v0.0.3"
fi

devnet_flag=""
if [ -n "$devnet" ]; then
        devnet_flag="--devnet $devnet"
fi

# Set aggregator flag based on isAggregator value
aggregator_flag=""
if [ "$isAggregator" == "true" ]; then
    aggregator_flag="--is-aggregator"
fi

# Set attestation committee count flag if explicitly configured
attestation_committee_flag=""
if [ -n "$attestationCommitteeCount" ]; then
    attestation_committee_flag="--attestation-committee-count $attestationCommitteeCount"
fi

# Set checkpoint sync URL when restarting with checkpoint sync
checkpoint_sync_flag=""
if [ -n "${checkpoint_sync_url:-}" ]; then
    checkpoint_sync_flag="--checkpoint-sync-url $checkpoint_sync_url"
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
        --http-port $apiPort \
        --log-level info \
        --hash-sig-key-dir $configDir/hash-sig-keys \
        $attestation_committee_flag \
        $aggregator_flag \
        $checkpoint_sync_flag"

node_docker="$docker_image --data-dir /data \
        --genesis-config /config/config.yaml \
        --validator-registry-path /config/validators.yaml \
        --genesis-state /config/genesis.ssz \
        --validator-config /config/validator-config.yaml \
        $devnet_flag \
        --nodes-path /config/nodes.yaml \
        --node-id $item --node-key-path /config/$privKeyPath \
        --listen-address /ip4/0.0.0.0/udp/$quicPort/quic-v1 \
        --metrics-port $metricsPort \
        --http-port $apiPort \
        --log-level info \
        --hash-sig-key-dir /config/hash-sig-keys \
        $attestation_committee_flag \
        $aggregator_flag \
        $checkpoint_sync_flag"

if [ -z "$node_setup" ]; then
    node_setup="docker"
fi
