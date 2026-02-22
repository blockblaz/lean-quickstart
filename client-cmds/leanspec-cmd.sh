#!/bin/bash

#-----------------------leanspec setup----------------------
# leanSpec (Python) consensus client - same volume layout as zeam/ethlambda.
# Build the image from leanSpec repo: docker build --target node -t lean-spec:node .
# Or use a published image and set LEAN_SPEC_IMAGE env var.

LEAN_SPEC_IMAGE="${LEAN_SPEC_IMAGE:-0xpartha/leanSpec-node:latest}"

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

# Command when running as binary
node_binary="uv run python -m lean_spec \
    --custom-network-config-dir $configDir \
    --gossipsub-port $quicPort \
    --node-id $item \
    --node-key $configDir/$item.key \
    --metrics-address 0.0.0.0 \
    --metrics-port $metricsPort \
    $aggregator_flag \
    $checkpoint_sync_flag"

# Command when running as docker container
node_docker="$LEAN_SPEC_IMAGE \
    --custom-network-config-dir /config \
    --gossipsub-port $quicPort \
    --node-id $item \
    --node-key /config/$item.key \
    --metrics-address 0.0.0.0 \
    --metrics-port $metricsPort \
    $aggregator_flag \
    $checkpoint_sync_flag"

node_setup="docker"
