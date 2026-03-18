#!/bin/bash

# Metrics enabled by default if not strictly disabled
metrics_flag=""
if [ "$enableMetrics" != "false" ]; then
  metrics_flag="--metrics-port $metricsPort"
fi

# Set aggregator flag based on isAggregator value
aggregator_flag=""
if [ "$isAggregator" == "true" ]; then
  aggregator_flag="--is-aggregator"
fi

# Set attestation committee count flag if explicitly configured
attestation_committee_flag=""
if [ -n "$attestationCommitteeCount" ]; then
  attestation_committee_flag="--attestation-committee-count $attestationCommitteeCount"
fi

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
      --listen-addr \"/ip4/0.0.0.0/udp/$quicPort/quic-v1\" \
      --discovery-port $quicPort \
      --devnet-id \"${devnet:-devnet0}\" \
      --api-port $apiPort \
      $metrics_flag \
      $attestation_committee_flag \
      $aggregator_flag"

# Docker command (assumes image entrypoint handles the binary)
node_docker="ghcr.io/geanlabs/gean:devnet3 \
      --data-dir /data \
      --genesis /config/config.yaml \
      --bootnodes /config/nodes.yaml \
      --validator-registry-path /config/validators.yaml \
      --node-id $item \
      --node-key /config/$privKeyPath \
      --validator-keys /config/hash-sig-keys \
      --listen-addr /ip4/0.0.0.0/udp/$quicPort/quic-v1 \
      --discovery-port $quicPort \
      --devnet-id ${devnet:-devnet0} \
      --api-port $apiPort \
      $metrics_flag \
      $attestation_committee_flag \
      $aggregator_flag"

node_setup="docker"