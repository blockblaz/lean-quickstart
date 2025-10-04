#!/bin/bash

#-----------------------ream setup----------------------
node_binary=
node_docker="ghcr.io/reamlabs/ream:latest --data-dir /data \
        lean_node \
        --network /config/config.yaml \
        --validator-registry-path /config/validators.yaml \
        --bootnodes /config/nodes.yaml \
        --node-id $item --node-key /config/$privKeyPath \
        --socket-port $quicPort"

# choose either binary or docker
node_setup="docker"