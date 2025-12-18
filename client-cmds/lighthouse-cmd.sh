#!/bin/bash
node_binary="$lighthouse_bin lean_node \
      --datadir \"$dataDir/$item\" \
      --config \"$configDir/config.yaml\" \
      --validators \"$configDir/validator-config.yaml\" \
      --nodes \"$configDir/nodes.yaml\" \
      --node-id \"$item\" \
      --private-key \"$configDir/$privKeyPath\" \
      --genesis-json \"$configDir/genesis.json\" \
      --socket-port $quicPort"

node_docker="sigmaprime/lighthouse:sigp-pr-8600-fa2fa57 lighthouse lean_node \
      --datadir /data \
      --config /config/config.yaml \
      --validators /config/validator-config.yaml \
      --nodes /config/nodes.yaml \
      --node-id $item \
      --private-key /config/$privKeyPath \
      --genesis-json /config/genesis.json \
      --socket-port $quicPort"

node_setup="docker"
