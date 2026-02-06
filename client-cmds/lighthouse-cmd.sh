#!/bin/bash

# Metrics enabled by default
metrics_flag="--metrics"

# Docker image (set from validator-config.yaml or user config via --configFile)
# lighthouseImage is exported by spin-node.sh before sourcing this file

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
      --metrics-port $metricsPort"

node_docker="$lighthouseImage lighthouse lean_node \
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
      --metrics-port $metricsPort"

node_setup="docker"
