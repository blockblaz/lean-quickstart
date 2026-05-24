#!/bin/bash

#-----------------------zeam setup----------------------
# setup where lean-quickstart is a submodule folder in zeam repo
# update the path to your binary here if you want to use binary
# Metrics enabled by default
metrics_flag="--metrics-enable"

# Optional global zeam CLI flags before `node` (e.g. --console-log-level debug).
# Default empty: blockblaz/zeam:devnet4 and older binaries do not support top-level log flags.
# With a current zeam build: export ZEAM_GLOBAL_FLAGS='--console-log-level debug'
zeam_global_flags="${ZEAM_GLOBAL_FLAGS:-}"

# Set aggregator flag based on isAggregator value
aggregator_flag=""
if [ "$isAggregator" == "true" ]; then
    aggregator_flag="--is-aggregator"
fi

# Aggregators subscribe only to their committee subnet (validator_index %
# attestation_committee_count). parse-vc.sh exports that single id in
# aggregateSubnetIds when isAggregator is true.
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

# On-disk database engine (requires a zeam build that supports --db-backend).
# Override with e.g. ZEAM_DB_BACKEND=rocksdb for RocksDB.
zeam_db_backend="${ZEAM_DB_BACKEND:-lmdb}"
db_backend_flag="--db-backend ${zeam_db_backend}"

# Chain-worker thread routing (zeam #803 slice c-2b/c-2c).
#
# When `on`, zeam runs gossip-block + gossip-attestation producer-side
# handlers through a dedicated worker thread that owns the
# BeamChain.states map; cross-thread readers (HTTP API, metrics scrape,
# event broadcaster) skip the rwlock and use refcount-gated borrows.
# This is the prod path post-c-2b; the c-2c part 2 burn-in on devnet4
# is what validates it under sustained gossip pressure. Watch:
# `zeam_lock_hold_seconds{site="onBlock.commit"}` p99 (should drop
# dramatically vs slice (b) baseline), `lean_chain_state_refcount_distribution`
# (typical=1, never >16), and `lean_chain_queue_dropped_total` (should
# stay 0 under nominal load).
#
# Default empty/on: omit --chain-worker so zeam uses its compiled-in
# default (enabled post-PR #830). Do NOT pass `--chain-worker on` —
# zeam's bool flag does not take on/off values and "on" breaks parsing
# of subsequent flags such as --rayon-threads.
#
# Override via `export ZEAM_CHAIN_WORKER=off` to emit
# `--chain-worker false` (legacy synchronous kill-switch).
#
# Note `${VAR-default}` (no colon) so an explicitly-empty
# `ZEAM_CHAIN_WORKER=` suppresses the flag entirely.
zeam_chain_worker="${ZEAM_CHAIN_WORKER-on}"
chain_worker_flag=""
case "$zeam_chain_worker" in
    on|"")
        # Enabled (compiled default); omit flag.
        ;;
    off|false)
        chain_worker_flag="--chain-worker false"
        ;;
    *)
        echo "WARN(zeam-cmd): ZEAM_CHAIN_WORKER='$zeam_chain_worker' is not 'on', 'off', 'false', or empty; ignoring (no --chain-worker flag passed)" >&2
        ;;
esac

# Rayon worker count for the multisig (XMSS) aggregate prover (zeam #903 / #899).
#
# Default unset → zeam picks an auto-split that gives roughly half of the
# post-system-thread CPU budget to rayon and half to its Zig worker pool. That
# split is fine for non-aggregators (which mostly verify, also via rayon-from-
# Zig-workers) but underuses CPU on CPU-rich aggregators where the produce-path
# FFI is the per-slot bottleneck.
#
# Aggregators default to 12 rayon threads; non-aggregators stay on zeam's
# auto-split unless overridden:
#   - ZEAM_RAYON_THREADS_AGGREGATOR  # aggregator override (default 12)
#   - ZEAM_RAYON_THREADS             # uniform override for both roles
# For aggregators, ZEAM_RAYON_THREADS_AGGREGATOR wins when set; otherwise 12.
#
# Sizing guidance for a 16-vCPU host: 12 is the recommended starting point
# (cpu_count - 4 reserved system threads: libxev/libp2p/api/metrics). Do not
# exceed cpu_count - 4 or those reserved threads start to starve, surfacing as
# `zeam_fork_choice_tick_interval_duration_seconds` p99 climbing.
#
# REQUIRES: a zeam build with PR #903 merged plus a docker image cut from it.
# Older images do not recognise `--rayon-threads` and will fail to start. Leave
# both env vars unset to suppress the flag entirely for pre-#903 images.
rayon_threads_flag=""
if [ "$isAggregator" == "true" ]; then
    rayon_threads_flag="--rayon-threads ${ZEAM_RAYON_THREADS_AGGREGATOR:-12}"
elif [ -n "${ZEAM_RAYON_THREADS:-}" ]; then
    rayon_threads_flag="--rayon-threads $ZEAM_RAYON_THREADS"
fi

node_binary="$scriptDir/../zig-out/bin/zeam $zeam_global_flags node \
      --custom-genesis $configDir \
      --validator-config $validatorConfig \
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
      $chain_worker_flag \
      $rayon_threads_flag"

node_docker="--security-opt seccomp=unconfined blockblaz/zeam:devnet4 $zeam_global_flags node \
      --custom-genesis /config \
      --validator-config $validatorConfig \
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
      $chain_worker_flag \
      $rayon_threads_flag"

# choose either binary or docker
node_setup="docker"
