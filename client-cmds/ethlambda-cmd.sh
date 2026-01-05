#!/bin/bash

#-----------------------ethlambda setup----------------------

binary_path="/Users/mega/lean_consensus/ethlambda/target/debug/ethlambda"

# Command when running as binary
node_binary="$binary_path \
      --custom-genesis-json-file \"$configDir/genesis.json\" \
      --bootnodes-file \"$configDir/nodes.yaml\"
"

# Command when running as docker container
# TODO: fill in docker command
node_docker="--------------"

node_setup="binary"
