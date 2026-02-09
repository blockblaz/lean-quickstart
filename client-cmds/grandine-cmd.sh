#!/bin/bash

# Docker image (set from deploy-validator-config.yaml, merged from validator-config.yaml + user config)
# grandineImage is exported by spin-node.sh before sourcing this file

node_binary="$grandine_bin \
        --genesis $configDir/config.yaml \
        --validator-registry-path $configDir/validators.yaml \
        --bootnodes $configDir/nodes.yaml \
        --node-id $item \
        --node-key $configDir/$privKeyPath \
        --port $quicPort \
        --address 0.0.0.0 \
        --metrics \
        --http-address 0.0.0.0 \
        --http-port $metricsPort \
        --hash-sig-key-dir $configDir/hash-sig-keys"

node_docker="$grandineImage \
        --genesis /config/config.yaml \
        --validator-registry-path /config/validators.yaml \
        --bootnodes /config/nodes.yaml \
        --node-id $item \
        --node-key /config/$privKeyPath \
        --port $quicPort \
        --address 0.0.0.0 \
        --metrics \
        --http-address 0.0.0.0 \
        --http-port $metricsPort \
        --hash-sig-key-dir /config/hash-sig-keys"

# choose either binary or docker
node_setup="docker"
