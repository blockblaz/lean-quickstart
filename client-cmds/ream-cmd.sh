#!/bin/bash

#-----------------------ream setup----------------------
# Metrics enabled by default
metrics_flag="--metrics"

# Docker image (set from deploy-validator-config.yaml, merged from validator-config.yaml + user config)
# reamImage is exported by spin-node.sh before sourcing this file

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
        --http-address 0.0.0.0"

node_docker="$reamImage --data-dir /data \
        lean_node \
        --network /config/config.yaml \
        --validator-registry-path /config/validators.yaml \
        --bootnodes /config/nodes.yaml \
        --node-id $item --node-key /config/$privKeyPath \
        --socket-port $quicPort \
        $metrics_flag \
        --metrics-address 0.0.0.0 \
        --metrics-port $metricsPort \
        --http-address 0.0.0.0"

# choose either binary or docker
node_setup="docker"
