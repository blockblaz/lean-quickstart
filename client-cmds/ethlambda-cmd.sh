#!/bin/bash

#-----------------------ethlambda setup----------------------

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
node_docker="ghcr.io/lambdaclass/ethlambda:latest \
      --custom-network-config-dir /config \
      --gossipsub-port $quicPort \
      --node-id $item \
      --node-key /config/$item.key \
      --metrics-address 0.0.0.0 \
      --metrics-port $metricsPort"

node_setup="docker"
