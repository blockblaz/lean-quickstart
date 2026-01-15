#!/bin/bash

node_binary="$grandine_bin \
        --genesis $configDir/config.yaml \
        --validator-registry-path $configDir/validators.yaml \
        --bootnodes $configDir/nodes.yaml \
        --node-id $item \
        --node-key $configDir/$privKeyPath \
        --port $quicPort \
        --address 0.0.0.0 \
        --hash-sig-key-dir $configDir/hash-sig-keys"

node_docker="sifrai/lean:unstable \
        --genesis /config/config.yaml \
        --validator-registry-path /config/validators.yaml \
        --bootnodes /config/nodes.yaml \
        --node-id $item \
        --node-key /config/$privKeyPath \
        --port $quicPort \
        --address 0.0.0.0 \
        --hash-sig-key-dir /config/hash-sig-keys"

# choose either binary or docker
node_setup="docker"
