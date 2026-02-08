#!/bin/bash

#-----------------------ream setup----------------------
# Metrics enabled by default
metrics_flag="--metrics"

# Set aggregator flag based on isAggregator value
aggregator_flag=""
if [ "$isAggregator" == "true" ]; then
    aggregator_flag="--is-aggregator"
fi

# modify the path to the ream binary as per your system
node_binary="$scriptDir/../ream/target/release/ream --data-dir $dataDir/$item \
        lean_node \
        --network $configDir/config.yaml \
        --validator-registry-path $configDir/validators.yaml \
        --bootnodes $configDir/nodes.yaml \
        --node-id $item --node-key $configDir/$privKeyPath \
        --socket-port $quicPort \
        $metrics_flag \
        --metrics-address 0.0.0.0 \
        --metrics-port $metricsPort \
        --http-address 0.0.0.0 \
        --attestation-committee-count $attestationCommitteeCount \
        $aggregator_flag"

node_docker="ghcr.io/reamlabs/ream:latest-devnet2 --data-dir /data \
        lean_node \
        --network /config/config.yaml \
        --validator-registry-path /config/validators.yaml \
        --bootnodes /config/nodes.yaml \
        --node-id $item --node-key /config/$privKeyPath \
        --socket-port $quicPort \
        $metrics_flag \
        --metrics-address 0.0.0.0 \
        --metrics-port $metricsPort \
        --http-address 0.0.0.0 \
        --attestation-committee-count $attestationCommitteeCount \
        $aggregator_flag"

# choose either binary or docker
node_setup="docker"
