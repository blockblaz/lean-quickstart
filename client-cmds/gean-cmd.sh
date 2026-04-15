#!/bin/bash

#-----------------------gean setup----------------------
binary_path="$scriptDir/../gean/bin/gean"

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

# Command when running as binary
node_binary="$binary_path \
      -custom-network-config-dir $configDir \
      -gossipsub-port $quicPort \
      -node-id $item \
      -node-key $configDir/$item.key \
      -http-address 0.0.0.0 \
      -api-port $apiPort \
      -metrics-port $metricsPort \
      $attestation_committee_flag \
      $aggregator_flag \
      $checkpoint_sync_flag"

# Command when running as docker container
node_docker="ghcr.io/geanlabs/gean:devnet4 \
      -custom-network-config-dir /config \
      -gossipsub-port $quicPort \
      -node-id $item \
      -node-key /config/$item.key \
      -http-address 0.0.0.0 \
      -api-port $apiPort \
      -metrics-port $metricsPort \
      $attestation_committee_flag \
      $aggregator_flag \
      $checkpoint_sync_flag"

node_setup="docker"