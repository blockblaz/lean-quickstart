#!/bin/bash

#-----------------------ream setup----------------------
# Metrics enabled by default
metrics_flag="--metrics"

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

# modify the path to the ream binary as per your system
node_binary="$scriptDir/../ream/target/release/ream --data-dir $dataDir/$item \
        lean_node \
        --network $configDir/config.yaml \
        --validator-registry-path $configDir/annotated_validators.yaml \
        --bootnodes $configDir/nodes.yaml \
        --node-id $item --node-key $configDir/$privKeyPath \
        --socket-port $quicPort \
        $metrics_flag \
        --metrics-address 0.0.0.0 \
        --metrics-port $metricsPort \
        --http-address 0.0.0.0 \
        --http-port $apiPort \
        $attestation_committee_flag \
        $aggregator_flag \
        $aggregate_subnet_ids_flag \
        $checkpoint_sync_flag"

node_docker="ghcr.io/reamlabs/ream:latest-devnet4 --data-dir /data \
        lean_node \
        --network /config/config.yaml \
        --validator-registry-path /config/annotated_validators.yaml \
        --bootnodes /config/nodes.yaml \
        --node-id $item --node-key /config/$privKeyPath \
        --socket-port $quicPort \
        $metrics_flag \
        --metrics-address 0.0.0.0 \
        --metrics-port $metricsPort \
        --http-address 0.0.0.0 \
        --http-port $apiPort \
        $attestation_committee_flag \
        $aggregator_flag \
        $aggregate_subnet_ids_flag \
        $checkpoint_sync_flag"

# choose either binary or docker
node_setup="docker"
