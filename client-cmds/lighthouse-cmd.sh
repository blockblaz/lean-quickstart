#!/bin/bash

# Metrics enabled by default
metrics_flag="--metrics"

# Set aggregator flag based on isAggregator value
aggregator_flag=""
if [ "$isAggregator" == "true" ]; then
    aggregator_flag="--is-aggregator"
fi

node_binary="$lighthouse_bin lean_node \
      --datadir \"$dataDir/$item\" \
      --config \"$configDir/config.yaml\" \
      --validators \"$configDir/validator-config.yaml\" \
      --nodes \"$configDir/nodes.yaml\" \
      --node-id \"$item\" \
      --private-key \"$configDir/$privKeyPath\" \
      --genesis-json \"$configDir/genesis.json\" \
      --socket-port $quicPort\
      $metrics_flag \
      --metrics-address 0.0.0.0 \
      --metrics-port $metricsPort \
      --attestation-committee-count $attestationCommitteeCount \
      $aggregator_flag"

node_docker="hopinheimer/lighthouse:latest lighthouse lean_node \
      --datadir /data \
      --config /config/config.yaml \
      --validators /config/validator-config.yaml \
      --nodes /config/nodes.yaml \
      --node-id $item \
      --private-key /config/$privKeyPath \
      --genesis-json /config/genesis.json \
      --socket-port $quicPort\
      $metrics_flag \
      --metrics-address 0.0.0.0 \
      --metrics-port $metricsPort \
      --attestation-committee-count $attestationCommitteeCount \
      $aggregator_flag"

node_setup="docker"
