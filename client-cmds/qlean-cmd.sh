#!/bin/bash

#-----------------------qlean setup----------------------
# expects "qlean" submodule or symlink inside "lean-quickstart" root directory
# https://github.com/qdrvm/qlean-mini

# Platform-specific qlean image
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    QLEAN_IMAGE="qdrvm/qlean-mini:devnet-4-amd64"
elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    QLEAN_IMAGE="qdrvm/qlean-mini:devnet-4-arm64"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
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

# Set checkpoint sync URL when restarting with checkpoint sync
checkpoint_sync_flag=""
if [ -n "${checkpoint_sync_url:-}" ]; then
    checkpoint_sync_flag="--checkpoint-sync-url $checkpoint_sync_url"
fi

node_binary="$scriptDir/qlean/build/out/bin/qlean \
      --genesis-dir $configDir \
      --data-dir $dataDir/$item \
      --node-id $item --node-key $configDir/$privKeyPath \
      --listen-addr /ip4/0.0.0.0/udp/$quicPort/quic-v1 \
      --metrics-host 0.0.0.0 \
      --metrics-port $metricsPort \
      --api-host 0.0.0.0 \
      --api-port $apiPort \
      $attestation_committee_flag \
      $aggregator_flag \
      $checkpoint_sync_flag \
      -ldebug"

node_docker="$QLEAN_IMAGE \
      --genesis-dir /config \
      --data-dir /data \
      --node-id $item --node-key /config/$privKeyPath \
      --listen-addr /ip4/0.0.0.0/udp/$quicPort/quic-v1 \
      --metrics-host 0.0.0.0 \
      --metrics-port $metricsPort \
      --api-host 0.0.0.0 \
      --api-port $apiPort \
      $attestation_committee_flag \
      $aggregator_flag \
      $checkpoint_sync_flag \
      -ldebug"

# choose either binary or docker
node_setup="docker"
