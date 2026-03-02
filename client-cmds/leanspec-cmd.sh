#!/bin/bash

#-----------------------leanspec setup----------------------
# leanSpec (Python) consensus client - same volume layout as zeam/ethlambda.
# Build the image from leanSpec repo: docker build --target node -t lean-spec:node .
# Or use a published image and set LEAN_SPEC_IMAGE env var.

LEAN_SPEC_IMAGE="${LEAN_SPEC_IMAGE:-ghcr.io/leanethereum/leanspec-node:devnet3}"

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

# Bootnodes: use multiaddrs from validator-config so every node can reach every other.
# nodes.yaml ENRs use a "quic" key; leanSpec's ENR parser only supports "udp", so it rejects
# those ENRs with "ENR has no UDP connection info". Passing multiaddrs avoids ENR parsing.
# Fallback to zeam's default port for local two-node dev.
bootnode_arg=""
vc_file="${configDir}/validator-config.yaml"
if [ -f "$vc_file" ] && command -v yq &>/dev/null; then
    while IFS= read -r ma; do
        [ -n "$ma" ] && bootnode_arg="$bootnode_arg --bootnode $ma"
    done < <(yq eval '.validators[] | select(.name != "'"$item"'") | "/ip4/" + .enrFields.ip + "/udp/" + (.enrFields.quic | tostring) + "/quic-v1"' "$vc_file" 2>/dev/null || true)
fi
if [ -z "$bootnode_arg" ]; then
    bootnode_arg="--bootnode /ip4/127.0.0.1/udp/9001/quic-v1"
fi

# leanSpec CLI: --genesis (required), --listen, --validator-keys, --node-id, etc.
# See: python -m lean_spec --help
node_binary="uv run python -m lean_spec \
    --genesis $configDir/config.yaml \
    --listen /ip4/0.0.0.0/udp/$quicPort/quic-v1 \
    --node-id $item \
    --validator-keys $configDir \
    $bootnode_arg \
    $aggregator_flag \
    $checkpoint_sync_flag"

# Command when running as docker container (same args, paths under /config and /data)
node_docker="$LEAN_SPEC_IMAGE \
    --genesis /config/config.yaml \
    --listen /ip4/0.0.0.0/udp/$quicPort/quic-v1 \
    --node-id $item \
    --validator-keys /config \
    $bootnode_arg \
    $aggregator_flag \
    $checkpoint_sync_flag"

node_setup="docker"
