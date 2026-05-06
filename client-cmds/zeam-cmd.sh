#!/bin/bash

#-----------------------zeam setup----------------------
# setup where lean-quickstart is a submodule folder in zeam repo
# update the path to your binary here if you want to use binary
# Metrics enabled by default
metrics_flag="--metrics_enable"

# Optional global zeam CLI flags before `node` (e.g. --console-log-level debug).
# Default empty: blockblaz/zeam:devnet4 and older binaries do not support top-level log flags.
# With a current zeam build: export ZEAM_GLOBAL_FLAGS='--console-log-level debug'
zeam_global_flags="${ZEAM_GLOBAL_FLAGS:-}"

# Set aggregator flag based on isAggregator value
aggregator_flag=""
if [ "$isAggregator" == "true" ]; then
    aggregator_flag="--is-aggregator"
fi

# In multi-subnet deployments, an aggregator must subscribe to every subnet's
# attestation topics so it can aggregate votes from all committees. The caller
# (spin-node.sh / ansible roles) exports aggregateSubnetIds as a CSV of the
# full subnet id set for the network.
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

# On-disk database engine (requires a zeam build that supports --db-backend).
# Override with e.g. ZEAM_DB_BACKEND=rocksdb for RocksDB.
zeam_db_backend="${ZEAM_DB_BACKEND:-lmdb}"
db_backend_flag="--db-backend ${zeam_db_backend}"

# Chain-worker thread routing (zeam #803 slice c-2b/c-2c).
#
# When `ZEAM_CHAIN_WORKER=on`, zeam runs gossip-block + gossip-attestation
# producer-side handlers through a dedicated worker thread that owns the
# BeamChain.states map; cross-thread readers (HTTP API, metrics scrape,
# event broadcaster) skip the rwlock and use refcount-gated borrows. Aim
# is the c-2c part 2 burn-in: ≥24h on devnet4 with this flag on, watching
# `zeam_lock_hold_seconds{site="onBlock.commit"}` p99 (should drop) and
# `lean_chain_state_refcount_distribution` (typical=1, never >16).
#
# Default empty: this PR is a strict no-op against any zeam build,
# including the currently-published `zeam:devnet4` (v0.4.13, pre-c-1)
# which does not recognise `--chain-worker` at all. The flag is ONLY
# emitted when ZEAM_CHAIN_WORKER is explicitly set to `on` or `off`.
#
# To enable the burn-in once v0.4.14 (or later) is published as
# `blockblaz/zeam:devnet4`:
#   export ZEAM_CHAIN_WORKER=on
# before running spin-node.sh / ansible. To explicitly request the
# legacy synchronous path on a c-1+ build (kill-switch):
#   export ZEAM_CHAIN_WORKER=off
zeam_chain_worker="${ZEAM_CHAIN_WORKER:-}"
chain_worker_flag=""
case "$zeam_chain_worker" in
    on|off)
        chain_worker_flag="--chain-worker $zeam_chain_worker"
        ;;
    "")
        # Unset / empty — no flag, zeam takes its compiled-in default
        # (which is `off` for the chain-worker per #828).
        ;;
    *)
        echo "WARN(zeam-cmd): ZEAM_CHAIN_WORKER='$zeam_chain_worker' is not 'on' or 'off'; ignoring (no --chain-worker flag passed)" >&2
        ;;
esac

node_binary="$scriptDir/../zig-out/bin/zeam $zeam_global_flags node \
      --custom_genesis $configDir \
      --validator_config $validatorConfig \
      --data-dir $dataDir/$item \
      --node-id $item --node-key $configDir/$item.key \
      $metrics_flag \
      --api-port $apiPort \
      --metrics-port $metricsPort \
      $attestation_committee_flag \
      $aggregator_flag \
      $aggregate_subnet_ids_flag \
      $checkpoint_sync_flag \
      $db_backend_flag \
      $chain_worker_flag"

node_docker="--security-opt seccomp=unconfined blockblaz/zeam:devnet4 $zeam_global_flags node \
      --custom_genesis /config \
      --validator_config $validatorConfig \
      --data-dir /data \
      --node-id $item --node-key /config/$item.key \
      $metrics_flag \
      --api-port $apiPort \
      --metrics-port $metricsPort \
      $attestation_committee_flag \
      $aggregator_flag \
      $aggregate_subnet_ids_flag \
      $checkpoint_sync_flag \
      $db_backend_flag \
      $chain_worker_flag"

# choose either binary or docker
node_setup="docker"
