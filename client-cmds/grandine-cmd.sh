#!/bin/bash

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

node_binary="$grandine_bin \
        --genesis $configDir/config.yaml \
        --validator-registry-path $configDir/validators.yaml \
        --bootnodes $configDir/nodes.yaml \
        --node-id $item \
        --node-key $configDir/$privKeyPath \
        --port $quicPort \
        --address 0.0.0.0 \
        --metrics \
        --http-address 0.0.0.0 \
        --http-port $metricsPort \
        --hash-sig-key-dir $configDir/hash-sig-keys \
        $attestation_committee_flag \
        $aggregator_flag"

node_docker="sifrai/lean:devnet-2 \
        --genesis /config/config.yaml \
        --validator-registry-path /config/validators.yaml \
        --bootnodes /config/nodes.yaml \
        --node-id $item \
        --node-key /config/$privKeyPath \
        --port $quicPort \
        --address 0.0.0.0 \
        --metrics \
        --http-address 0.0.0.0 \
        --http-port $metricsPort \
        --hash-sig-key-dir /config/hash-sig-keys \
        $attestation_committee_flag \
        $aggregator_flag"

# choose either binary or docker
node_setup="docker"
