#!/bin/bash

# Set aggregator flag based on isAggregator value
aggregator_flag=""
if [ "$isAggregator" == "true" ]; then
    aggregator_flag="--is-aggregator"
fi

# Set checkpoint sync URL when restarting with checkpoint sync
checkpoint_sync_flag=""
if [ -n "${checkpoint_sync_url:-}" ]; then
    checkpoint_sync_flag="--checkpoint-sync-url $checkpoint_sync_url"
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
        $aggregator_flag \
        $checkpoint_sync_flag"

node_docker="$grandineImage \
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
        $aggregator_flag \
        $checkpoint_sync_flag"

# choose either binary or docker
node_setup="docker"
