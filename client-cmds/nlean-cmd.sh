#!/bin/bash

#-----------------------nlean setup----------------------
# This script follows lean-quickstart's client-cmd contract:
# it must populate node_binary / node_docker / node_setup.
# NLEAN_REPO should point to this repository when lean-quickstart is outside this workspace.
# Default assumes sibling checkouts: <workspace>/nlean and <workspace>/lean-quickstart.
nlean_repo="${NLEAN_REPO:-$scriptDir/../nlean}"
nlean_docker_image="${NLEAN_DOCKER_IMAGE:-nlean-local:devnet3}"
nlean_network_name="${NLEAN_NETWORK_NAME:-devnet0}"
log_level="${NLEAN_LOG_LEVEL:-}"
enable_metrics="${enableMetrics:-false}"

enable_metrics=$(echo "$enable_metrics" | tr '[:upper:]' '[:lower:]')
if [[ "$enable_metrics" != "true" && "$enable_metrics" != "false" ]]; then
  enable_metrics="false"
fi

if [[ -z "${nlean_network_name// }" ]]; then
  nlean_network_name="devnet0"
fi

log_level="${log_level#${log_level%%[![:space:]]*}}"
log_level="${log_level%${log_level##*[![:space:]]}}"
log_level_arg=""
if [[ -n "$log_level" ]]; then
  log_level_arg="--log ${log_level}"
fi

node_private_key_path="${privKeyPath:-${item}.key}"

# Set aggregator flag based on isAggregator value (from parse-vc.sh)
aggregator_flag=""
if [[ "${isAggregator:-false}" == "true" ]]; then
  aggregator_flag="--is-aggregator"
fi

# Set attestation committee count flag if explicitly configured
attestation_committee_flag=""
if [[ -n "${attestationCommitteeCount:-}" ]]; then
  attestation_committee_flag="--attestation-committee-count $attestationCommitteeCount"
fi

# Set checkpoint sync URL when restarting with checkpoint sync
checkpoint_sync_flag=""
if [[ -n "${checkpoint_sync_url:-}" ]]; then
  checkpoint_sync_flag="--checkpoint-sync-url $checkpoint_sync_url"
fi

# Set API port flag if explicitly configured
api_port_flag=""
nlean_api_port="${NLEAN_API_PORT:-${httpPort:-}}"
if [[ -n "$nlean_api_port" ]]; then
  api_port_flag="--api-port $nlean_api_port"
fi

# Resolve the binary path
binary_path="$nlean_repo/artifacts/lean-client/Lean.Client"

mkdir -p "$dataDir/$item"

node_binary="$binary_path \
      --validator-config $configDir/validator-config.yaml \
      --node $item \
      --data-dir $dataDir/$item \
      --network $nlean_network_name \
      --node-key $configDir/$node_private_key_path \
      --socket-port $quicPort \
      --metrics $enable_metrics \
      --metrics-port $metricsPort \
      --metrics-address 0.0.0.0 \
      --hash-sig-key-dir $configDir/hash-sig-keys \
      $api_port_flag \
      $attestation_committee_flag \
      $aggregator_flag \
      $checkpoint_sync_flag \
      $log_level_arg"

nlean_docker_extra_env=""
if [[ -n "${NLEAN_DEBUG_DUMP_ATTESTATIONS:-}" ]]; then
  nlean_docker_extra_env+=" -e NLEAN_DEBUG_DUMP_ATTESTATIONS=${NLEAN_DEBUG_DUMP_ATTESTATIONS}"
fi
if [[ -n "${NLEAN_DEBUG_DUMP_DIR:-}" ]]; then
  nlean_docker_extra_env+=" -e NLEAN_DEBUG_DUMP_DIR=${NLEAN_DEBUG_DUMP_DIR}"
fi
if [[ -n "${NLEAN_DEBUG_DUMP_BLOCKS:-}" ]]; then
  nlean_docker_extra_env+=" -e NLEAN_DEBUG_DUMP_BLOCKS=${NLEAN_DEBUG_DUMP_BLOCKS}"
fi
if [[ -n "${NLEAN_DEBUG_DUMP_BLOCK_DIR:-}" ]]; then
  nlean_docker_extra_env+=" -e NLEAN_DEBUG_DUMP_BLOCK_DIR=${NLEAN_DEBUG_DUMP_BLOCK_DIR}"
fi
if [[ -n "${NLEAN_DEBUG_DUMP_OBSERVED_PROOFS:-}" ]]; then
  nlean_docker_extra_env+=" -e NLEAN_DEBUG_DUMP_OBSERVED_PROOFS=${NLEAN_DEBUG_DUMP_OBSERVED_PROOFS}"
fi
if [[ -n "${NLEAN_DEBUG_DUMP_OBSERVED_PROOFS_DIR:-}" ]]; then
  nlean_docker_extra_env+=" -e NLEAN_DEBUG_DUMP_OBSERVED_PROOFS_DIR=${NLEAN_DEBUG_DUMP_OBSERVED_PROOFS_DIR}"
fi
if [[ -n "${NLEAN_DEBUG_DUMP_OBSERVED_BLOCKS:-}" ]]; then
  nlean_docker_extra_env+=" -e NLEAN_DEBUG_DUMP_OBSERVED_BLOCKS=${NLEAN_DEBUG_DUMP_OBSERVED_BLOCKS}"
fi
if [[ -n "${NLEAN_DEBUG_DUMP_OBSERVED_BLOCKS_DIR:-}" ]]; then
  nlean_docker_extra_env+=" -e NLEAN_DEBUG_DUMP_OBSERVED_BLOCKS_DIR=${NLEAN_DEBUG_DUMP_OBSERVED_BLOCKS_DIR}"
fi

node_docker="${nlean_docker_extra_env} ${nlean_docker_image} \
      --validator-config /config/validator-config.yaml \
      --node $item \
      --data-dir /data \
      --network $nlean_network_name \
      --node-key /config/$node_private_key_path \
      --socket-port $quicPort \
      --metrics $enable_metrics \
      --metrics-port $metricsPort \
      --metrics-address 0.0.0.0 \
      --hash-sig-key-dir /config/hash-sig-keys \
      $api_port_flag \
      $attestation_committee_flag \
      $aggregator_flag \
      $checkpoint_sync_flag \
      $log_level_arg"

# choose either binary or docker
node_setup="${NLEAN_QUICKSTART_SETUP:-binary}"
