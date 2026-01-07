#!/bin/bash

#-----------------------ream setup----------------------
devnet_flag=""
if [ -n "$devnet" ]; then
        devnet_flag="--devnet $devnet"
fi

# Metrics enabled by default
metrics_flag="--metrics"

# modify the path to the ream binary as per your system
node_binary="$scriptDir/../ream/target/release/ream --data-dir $dataDir/$item \
        lean_node \
        --network $configDir/config.yaml \
        --validator-registry-path $configDir/validators.yaml \
        $devnet_flag \
        --bootnodes $configDir/nodes.yaml \
        --node-id $item --node-key $configDir/$privKeyPath \
        --socket-port $quicPort \
        $metrics_flag \
        --metrics-address 0.0.0.0 \
        --metrics-port $metricsPort \
        --http-address 0.0.0.0"

node_docker="ghcr.io/reamlabs/ream:latest --data-dir /data \
        lean_node \
        --network /config/config.yaml \
        --validator-registry-path /config/validators.yaml \
        $devnet_flag \
        --bootnodes /config/nodes.yaml \
        --node-id $item --node-key /config/$privKeyPath \
        --socket-port $quicPort \
        $metrics_flag \
        --metrics-address 0.0.0.0 \
        --metrics-port $metricsPort \
        --http-address 0.0.0.0"

# choose either binary or docker
node_setup="docker"
