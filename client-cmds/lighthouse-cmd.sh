#!/bin/bash

# Metrics enabled by default
metrics_flag="--metrics"

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

node_binary="$lighthouse_bin lean_node \
      --datadir \"$dataDir/$item\" \
      --config \"$configDir/config.yaml\" \
      --validators \"$configDir/deploy-validator-config.yaml\" \
      --nodes \"$configDir/nodes.yaml\" \
      --node-id \"$item\" \
      --private-key \"$configDir/$privKeyPath\" \
      --genesis-json \"$configDir/genesis.json\" \
      --socket-port $quicPort\
      $metrics_flag \
      --metrics-address 0.0.0.0 \
      --metrics-port $metricsPort \
      $aggregator_flag \
      $checkpoint_sync_flag"

node_docker="$lighthouseImage lighthouse lean_node \
      --datadir /data \
      --config /config/config.yaml \
      --validators /config/deploy-validator-config.yaml \
      --nodes /config/nodes.yaml \
      --node-id $item \
      --private-key /config/$privKeyPath \
      --genesis-json /config/genesis.json \
      --socket-port $quicPort\
      $metrics_flag \
      --metrics-address 0.0.0.0 \
      --metrics-port $metricsPort \
      $aggregator_flag \
      $checkpoint_sync_flag"

node_setup="docker"
