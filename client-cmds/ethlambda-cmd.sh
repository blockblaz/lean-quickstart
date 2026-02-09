#!/bin/bash

#-----------------------ethlambda setup----------------------

binary_path="$scriptDir/../ethlambda/target/release/ethlambda"

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

# Command when running as binary
node_binary="$binary_path \
      --custom-network-config-dir $configDir \
      --gossipsub-port $quicPort \
      --node-id $item \
      --node-key $configDir/$item.key \
      --metrics-address 0.0.0.0 \
      --metrics-port $metricsPort \
      $attestation_committee_flag \
      $aggregator_flag"

# Command when running as docker container
node_docker="ghcr.io/lambdaclass/ethlambda:devnet2 \
      --custom-network-config-dir /config \
      --gossipsub-port $quicPort \
      --node-id $item \
      --node-key /config/$item.key \
      --metrics-address 0.0.0.0 \
      --metrics-port $metricsPort \
      $attestation_committee_flag \
      $aggregator_flag"

node_setup="docker"
