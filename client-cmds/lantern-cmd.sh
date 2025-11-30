#!/bin/bash

#-----------------------lantern setup----------------------
LANTERN_REPO="https://github.com/Pier-Two/lantern.git"
LANTERN_BRANCH="main"
LANTERN_DIR="$scriptDir/lantern"

# Clone and build lantern if needed
build_lantern() {
    local need_build=false

    # Clone if not present
    if [ ! -d "$LANTERN_DIR" ]; then
        echo "   Cloning Lantern from $LANTERN_REPO..."
        git clone --recurse-submodules -b "$LANTERN_BRANCH" "$LANTERN_REPO" "$LANTERN_DIR"
        if [ $? -ne 0 ]; then
            echo "   Failed to clone Lantern"
            return 1
        fi
        need_build=true
    fi

    # Check if binary exists (for binary mode)
    if [ "$node_setup" == "binary" ] && [ ! -f "$LANTERN_DIR/zig-out/bin/lantern_cli" ]; then
        need_build=true
    fi

    # Check if docker image exists (for docker mode)
    if [ "$node_setup" == "docker" ]; then
        if ! docker images lantern:local --format "{{.Repository}}" | grep -q "lantern"; then
            need_build=true
        fi
    fi

    # Build if needed
    if [ "$need_build" == "true" ]; then
        echo "   Building Lantern..."
        cd "$LANTERN_DIR"

        if [ "$node_setup" == "binary" ]; then
            # Build binary with zig
            if ! command -v zig &> /dev/null; then
                echo "   Error: zig is required but not installed"
                return 1
            fi
            zig build -Doptimize=ReleaseFast
            if [ $? -ne 0 ]; then
                echo "   Failed to build Lantern binary"
                return 1
            fi
            echo "   Lantern binary built successfully"
        else
            # Build docker image
            docker build -t lantern:local .
            if [ $? -ne 0 ]; then
                echo "   Failed to build Lantern docker image"
                return 1
            fi
            echo "   Lantern docker image built successfully"
        fi

        cd "$scriptDir"
    fi

    return 0
}

devnet_flag=""
if [ -n "$devnet" ]; then
        devnet_flag="--devnet $devnet"
fi

# choose either binary or docker
node_setup="docker"

# Build lantern if needed
build_lantern
if [ $? -ne 0 ]; then
    echo "   Failed to prepare Lantern, exiting"
    exit 1
fi

# Binary path (after potential build)
node_binary="$LANTERN_DIR/zig-out/bin/lantern_cli --data-dir $dataDir/$item \
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
        --hash-sig-key-dir $configDir/hash-sig-keys"

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
        --hash-sig-key-dir /config/hash-sig-keys"
