#!/bin/bash

#-----------------------ream setup----------------------
node_binary=
REAM_TAG="${dockerTag:-latest}"
node_docker="ghcr.io/reamlabs/ream:${REAM_TAG} --data-dir /data \
        lean_node \
        --network /config/config.yaml \
        --validator-registry-path /config/validators.yaml \
        --bootnodes /config/nodes.yaml \
        --node-id $item --node-key /config/$privKeyPath \
        --socket-port $quicPort \
        --metrics-port $metricsPort"

# choose either binary or docker
node_setup="docker"