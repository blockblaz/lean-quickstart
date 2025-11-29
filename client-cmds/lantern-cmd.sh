#!/bin/bash

#-----------------------lantern setup----------------------
devnet_flag=""
if [ -n "$devnet" ]; then
        devnet_flag="--devnet $devnet"
fi

# Hash-sig key flags (if available)
hashsig_flags=""
if [ -n "$hashSigPkPath" ] && [ -n "$hashSigSkPath" ]; then
        hashsig_flags="--hash-sig-public $hashSigPkPath --hash-sig-secret $hashSigSkPath"
fi

hashsig_docker_flags=""
if [ -n "$hashSigKeyIndex" ]; then
        hashsig_docker_flags="--hash-sig-public /config/hash-sig-keys/validator_${hashSigKeyIndex}_pk.json --hash-sig-secret /config/hash-sig-keys/validator_${hashSigKeyIndex}_sk.json"
fi

# modify the path to the lantern binary as per your system
node_binary="$scriptDir/../../build/lantern_cli --data-dir $dataDir/$item \
        --genesis-config $configDir/config.yaml \
        --validator-registry-path $configDir/validators.yaml \
        --genesis-state $configDir/genesis.ssz \
        --validator-config $configDir/validator-config.yaml \
        $devnet_flag \
        --nodes-path $configDir/nodes.yaml \
        --node-id $item --node-key-path $configDir/$privKeyPath \
        --listen-address /ip4/0.0.0.0/udp/$quicPort/quic-v1 \
        --metrics-port $metricsPort \
        --http-port 5055 \
        $hashsig_flags"

node_docker="lantern:local --data-dir /data \
        --genesis-config /config/config.yaml \
        --validator-registry-path /config/validators.yaml \
        --genesis-state /config/genesis.ssz \
        --validator-config /config/validator-config.yaml \
        $devnet_flag \
        --nodes-path /config/nodes.yaml \
        --node-id $item --node-key-path /config/$privKeyPath \
        --listen-address /ip4/0.0.0.0/udp/$quicPort/quic-v1 \
        --metrics-port $metricsPort \
        --http-port 5055 \
        $hashsig_docker_flags"

# choose either binary or docker
node_setup="docker"
