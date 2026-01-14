#!/bin/bash

#-----------------------ethlambda setup----------------------

binary_path="/Users/mega/lean_consensus/ethlambda/target/debug/ethlambda"

# Command when running as binary
node_binary="$binary_path \
      --custom-network-config-dir $configDir \
      --gossipsub-port $quicPort \
      --node-key $configDir/$item.key \
      --metrics-address 0.0.0.0 \
      --metrics-port $metricsPort"

# Command when running as docker container
# TODO: fill in docker command
node_docker="--------------"

node_setup="binary"
