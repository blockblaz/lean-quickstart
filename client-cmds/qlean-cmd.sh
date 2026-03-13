#!/bin/bash

#-----------------------qlean setup----------------------
# expects "qlean" submodule or symlink inside "lean-quickstart" root directory
# https://github.com/qdrvm/qlean-mini

# Platform-specific qlean image (user-config.yml can override via docker_image)
if [ -z "$docker_image" ]; then
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        docker_image="qdrvm/qlean-mini:devnet-3-amd64"
    elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
        docker_image="qdrvm/qlean-mini:devnet-3-arm64"
    else
        echo "Unsupported architecture: $ARCH"
        exit 1
    fi
fi

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

node_binary="$scriptDir/qlean/build/src/executable/qlean \
      --modules-dir $scriptDir/qlean/build/src/modules \
      --genesis $configDir/config.yaml \
      --validator-registry-path $configDir/validators.yaml \
      --validator-keys-manifest $configDir/hash-sig-keys/validator-keys-manifest.yaml \
      --xmss-pk $hashSigPkPath \
      --xmss-sk $hashSigSkPath \
      --bootnodes $configDir/nodes.yaml \
      --data-dir $dataDir/$item \
      --node-id $item --node-key $configDir/$privKeyPath \
      --listen-addr /ip4/0.0.0.0/udp/$quicPort/quic-v1 \
      --prometheus-port $metricsPort \
      $attestation_committee_flag \
      $aggregator_flag \
      $checkpoint_sync_flag \
      -ldebug \
      -ltrace"
      
node_docker="$docker_image \
      --genesis /config/config.yaml \
      --validator-registry-path /config/validators.yaml \
      --validator-keys-manifest /config/hash-sig-keys/validator-keys-manifest.yaml \
      --xmss-pk /config/hash-sig-keys/validator_${hashSigKeyIndex}_pk.json \
      --xmss-sk /config/hash-sig-keys/validator_${hashSigKeyIndex}_sk.json \
      --bootnodes /config/nodes.yaml \
      --data-dir /data \
      --node-id $item --node-key /config/$privKeyPath \
      --listen-addr /ip4/0.0.0.0/udp/$quicPort/quic-v1 \
      --metrics-host 0.0.0.0 \
      --metrics-port $metricsPort \
      --api-host 0.0.0.0 \
      --api-port 5053 \
      $attestation_committee_flag \
      $aggregator_flag \
      $checkpoint_sync_flag \
      -ldebug \
      -ltrace"

if [ -z "$node_setup" ]; then
    node_setup="docker"
fi
