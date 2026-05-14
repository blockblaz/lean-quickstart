#!/bin/bash

#-----------------------ethlambda setup----------------------

binary_path="$scriptDir/../ethlambda/target/release/ethlambda"

# Set aggregator flag based on isAggregator value
aggregator_flag=""
if [ "$isAggregator" == "true" ]; then
    aggregator_flag="--is-aggregator"
fi

# In multi-subnet deployments, each aggregator subscribes to its OWN
# attestation subnet plus exactly ONE neighbor — subnet i covers
# {i, (i+1) mod attestation_committee_count}. Every subnet still has
# >=2 aggregators (own + previous's roving neighbor) while per-node
# gossip volume drops to 2/N. The caller (spin-node.sh / ansible roles)
# builds aggregateSubnetIds per-aggregator via the shared helper
# compute-aggregate-subnet-ids.sh. Background: blockblaz/zeam#863.
aggregate_subnet_ids_flag=""
if [ "$isAggregator" == "true" ] && [ -n "${aggregateSubnetIds:-}" ] && [[ "$aggregateSubnetIds" == *,* ]]; then
    aggregate_subnet_ids_flag="--aggregate-subnet-ids $aggregateSubnetIds"
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
      $aggregate_subnet_ids_flag \
      $checkpoint_sync_flag"

# Command when running as docker container
node_docker="ghcr.io/lambdaclass/ethlambda:devnet4 \
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
      $aggregate_subnet_ids_flag \
      $checkpoint_sync_flag"

node_setup="docker"
