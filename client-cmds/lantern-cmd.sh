#!/bin/bash

#-----------------------lantern setup----------------------
LANTERN_IMAGE="piertwo/lantern:v0.0.1"

# Pull lantern docker image if needed
pull_lantern() {
    if ! docker images "$LANTERN_IMAGE" --format "{{.Repository}}:{{.Tag}}" | grep -q "$LANTERN_IMAGE"; then
        echo "   Pulling Lantern image $LANTERN_IMAGE..."
        docker pull "$LANTERN_IMAGE"
        if [ $? -ne 0 ]; then
            echo "   Failed to pull Lantern image"
            return 1
        fi
        echo "   Lantern image pulled successfully"
    fi
    return 0
}

devnet_flag=""
if [ -n "$devnet" ]; then
        devnet_flag="--devnet $devnet"
fi

# Pull lantern image if needed
pull_lantern
if [ $? -ne 0 ]; then
    echo "   Failed to prepare Lantern, exiting"
    exit 1
fi

node_docker="$LANTERN_IMAGE --data-dir /data \
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
        --hash-sig-key-dir /config/hash-sig-keys"
