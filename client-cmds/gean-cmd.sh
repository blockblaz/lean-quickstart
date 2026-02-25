#!/bin/bash

# Metrics enabled by default if not strictly disabled
metrics_flag=""
if [ "$enableMetrics" != "false" ]; then
  metrics_flag="--metrics-port $metricsPort"
fi

# Gean uses --listen-addr for libp2p (TCP) and --discovery-port for Discv5 (UDP)
# We map $quicPort to the TCP listen port for consistency in port allocation

# Resolve binary path relative to the script location
# Fallback to absolute path if scriptDir is not available
BASE_DIR="${scriptDir:-$(pwd)}"
gean_bin="$BASE_DIR/../gean/bin/gean"

node_binary="$gean_bin \
      --data-dir \"$dataDir/$item\" \
      --genesis \"$configDir/config.yaml\" \
      --bootnodes \"$configDir/nodes.yaml\" \
      --validator-registry-path \"$configDir/validators.yaml\" \
      --node-id \"$item\" \
      --node-key \"$configDir/$privKeyPath\" \
      --validator-keys \"$configDir/hash-sig-keys\" \
      --listen-addr \"/ip4/0.0.0.0/tcp/$quicPort\" \
      --discovery-port $quicPort \
      --devnet-id \"${devnet:-devnet0}\" \
      $metrics_flag"

# Docker command (assumes image entrypoint handles the binary)
node_docker="ghcr.io/geanlabs/gean:devnet1 \
      --data-dir /data \
      --genesis /config/config.yaml \
      --bootnodes /config/nodes.yaml \
      --validator-registry-path /config/validators.yaml \
      --node-id $item \
      --node-key /config/$privKeyPath \
      --validator-keys /config/hash-sig-keys \
      --listen-addr /ip4/0.0.0.0/tcp/$quicPort \
      --discovery-port $quicPort \
      --devnet-id ${devnet:-devnet0} \
      $metrics_flag"

node_setup="docker" # Default to binary for now as per user workflow
