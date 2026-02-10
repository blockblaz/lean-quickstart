#!/bin/bash

#-----------------------lantern setup----------------------
# Docker image (set from deploy-validator-config.yaml or user config via --configFile)
# lanternImage is exported by spin-node.sh before sourcing this file

devnet_flag=""
if [ -n "$devnet" ]; then
        devnet_flag="--devnet $devnet"
fi

# Lantern's repo: https://github.com/Pier-Two/lantern
node_binary="$scriptDir/lantern/build/lantern_cli \
        --data-dir $dataDir/$item \
        --genesis-config $configDir/config.yaml \
        --validator-registry-path $configDir/validators.yaml \
        --genesis-state $configDir/genesis.ssz \
        --validator-config $configDir/deploy-validator-config.yaml \
        $devnet_flag \
        --nodes-path $configDir/nodes.yaml \
        --node-id $item --node-key-path $configDir/$privKeyPath \
        --listen-address /ip4/0.0.0.0/udp/$quicPort/quic-v1 \
        --metrics-port $metricsPort \
        --http-port 5055 \
        --log-level debug \
        --hash-sig-key-dir $configDir/hash-sig-keys"

node_docker="$lanternImage --data-dir /data \
        --genesis-config /config/config.yaml \
        --validator-registry-path /config/validators.yaml \
        --genesis-state /config/genesis.ssz \
        --validator-config /config/deploy-validator-config.yaml \
        $devnet_flag \
        --nodes-path /config/nodes.yaml \
        --node-id $item --node-key-path /config/$privKeyPath \
        --listen-address /ip4/0.0.0.0/udp/$quicPort/quic-v1 \
        --metrics-port $metricsPort \
        --http-port 5055 \
        --log-level debug \
        --hash-sig-key-dir /config/hash-sig-keys"

# choose either binary or docker
node_setup="docker"
