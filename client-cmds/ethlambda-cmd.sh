#!/bin/bash

#-----------------------ethlambda setup----------------------

# Docker image (set from deploy-validator-config.yaml, merged from validator-config.yaml + user config)
# ethlambdaImage is exported by spin-node.sh before sourcing this file

binary_path="$scriptDir/../ethlambda/target/release/ethlambda"

# Command when running as binary
node_binary="$binary_path \
      --custom-network-config-dir $configDir \
      --gossipsub-port $quicPort \
      --node-id $item \
      --node-key $configDir/$item.key \
      --metrics-address 0.0.0.0 \
      --metrics-port $metricsPort"

# Command when running as docker container
node_docker="$ethlambdaImage \
      --custom-network-config-dir /config \
      --gossipsub-port $quicPort \
      --node-id $item \
      --node-key /config/$item.key \
      --metrics-address 0.0.0.0 \
      --metrics-port $metricsPort"

node_setup="docker"
