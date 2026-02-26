#!/bin/bash

#-----------------------zeam setup----------------------
# setup where lean-quickstart is a submodule folder in zeam repo
# update the path to your binary here if you want to use binary
# Metrics enabled by default
metrics_flag="--metrics_enable"

# Set aggregator flag based on isAggregator value
aggregator_flag=""
if [ "$isAggregator" == "true" ]; then
    aggregator_flag="--is-aggregator"
fi

# Set checkpoint sync URL when restarting with checkpoint sync
checkpoint_sync_flag=""
if [ -n "${checkpoint_sync_url:-}" ]; then
    checkpoint_sync_flag="--checkpoint-sync-url $checkpoint_sync_url"
fi

# Set attestation committee count flag if explicitly configured
attestation_committee_flag=""
if [ -n "$attestationCommitteeCount" ]; then
    attestation_committee_flag="--attestation-committee-count $attestationCommitteeCount"
fi

node_binary="$scriptDir/../zig-out/bin/zeam node \
      --custom_genesis $configDir \
      --validator_config $validatorConfig \
      --data-dir $dataDir/$item \
      --node-id $item --node-key $configDir/$item.key \
      $metrics_flag \
      --api-port $metricsPort \
      $attestation_committee_flag \
      $aggregator_flag \
      $checkpoint_sync_flag"

node_docker="--security-opt seccomp=unconfined 0xpartha/zeam:devnet3 node \
      --custom_genesis /config \
      --validator_config $validatorConfig \
      --data-dir /data \
      --node-id $item --node-key /config/$item.key \
      $metrics_flag \
      --api-port $metricsPort \
      $attestation_committee_flag \
      $aggregator_flag \
      $checkpoint_sync_flag"

# choose either binary or docker
node_setup="docker"
