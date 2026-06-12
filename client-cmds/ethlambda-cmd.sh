#!/bin/bash

#-----------------------ethlambda setup----------------------

binary_path="$scriptDir/../ethlambda/target/release/ethlambda"

# Set aggregator flag based on isAggregator value
aggregator_flag=""
if [ "$isAggregator" == "true" ]; then
    aggregator_flag="--is-aggregator"
fi

# Aggregators subscribe only to their committee subnet (parse-vc.sh exports aggregateSubnetIds).
aggregate_subnet_ids_flag=""
if [ "$isAggregator" == "true" ] && [ -n "${aggregateSubnetIds:-}" ]; then
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
node_docker="ghcr.io/lambdaclass/ethlambda:devnet5 \
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

# Opt-in QUIC debug instrumentation for the gossipsub-wedge investigation.
# Enable with `DEBUG_QUIC=1 ./spin-node.sh ...`. Adds:
#   - RUST_LOG=quinn_proto=trace exposes the actual CONNECTION_CLOSE frame
#     (error_code, frame_type, reason) that the default `reason=error` log
#     line hides — needed to distinguish silent flow-control drops from
#     idle timeouts, protocol violations, or peer-initiated CCs.
#   - QLOGDIR writes per-connection qlog files (IETF QUIC event schema)
#     under $dataDir/$item/qlog so we can replay the timeline in qvis.
# Both are runtime-only env vars on the upstream image; no ethlambda source
# changes required.
nodeEnvFlags=""
# Truthy check: "1" / "true" / "yes" enable; "0" / "" / unset disable.
# Plain `-n` would treat the string "0" as enabled which is the opposite
# of what every other env-var-style toggle in this repo does.
case "${DEBUG_QUIC:-0}" in
  1|true|TRUE|yes|YES|on|ON)
    mkdir -p "$dataDir/$item/qlog"
    nodeEnvFlags="-e RUST_LOG=info,libp2p_quic=trace,quinn_proto=trace,quinn_udp=debug,libp2p_gossipsub=debug,libp2p_swarm=debug \
                  -e QLOGDIR=/data/qlog"
    ;;
esac

node_setup="docker"
