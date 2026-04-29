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

# Set checkpoint sync URL when restarting with checkpoint sync
checkpoint_sync_flag=""
if [ -n "${checkpoint_sync_url:-}" ]; then
    checkpoint_sync_flag="--checkpoint-sync-url $checkpoint_sync_url"
fi

# Command when running as binary
node_binary="$binary_path \
      --genesis $configDir/config.yaml \
      --validators $configDir/annotated_validators.yaml \
      --bootnodes $configDir/nodes.yaml \
      --validator-config $configDir/validator-config.yaml \
      --hash-sig-keys-dir $configDir/hash-sig-keys \
      --data-dir $dataDir/$item \
      --gossipsub-port $quicPort \
      --node-id $item \
      --node-key $configDir/$item.key \
      --http-address 0.0.0.0 \
      --api-port $apiPort \
      --metrics-port $metricsPort \
      $attestation_committee_flag \
      $aggregator_flag \
      $checkpoint_sync_flag"

# Command when running as docker container
node_docker="ghcr.io/lambdaclass/ethlambda:devnet3 \
      --genesis /config/config.yaml \
      --validators /config/annotated_validators.yaml \
      --bootnodes /config/nodes.yaml \
      --validator-config /config/validator-config.yaml \
      --hash-sig-keys-dir /config/hash-sig-keys \
      --data-dir /data \
      --gossipsub-port $quicPort \
      --node-id $item \
      --node-key /config/$item.key \
      --http-address 0.0.0.0 \
      --api-port $apiPort \
      --metrics-port $metricsPort \
      $attestation_committee_flag \
      $aggregator_flag \
      $checkpoint_sync_flag"

node_setup="docker"
