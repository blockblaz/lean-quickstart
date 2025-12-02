#!/bin/bash

#-----------------------qlean setup----------------------
# expects "qlean" submodule or symlink inside "lean-quickstart" root directory
# https://github.com/qdrvm/qlean-mini
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
      --prometheus-port $metricsPort"
      
node_docker="qdrvm/qlean-mini:devnet-1 \
      --genesis /config/config.yaml \
      --validator-registry-path /config/validators.yaml \
      --validator-keys-manifest /config/hash-sig-keys/validator-keys-manifest.yaml \
      --xmss-pk /config/hash-sig-keys/validator_${hashSigKeyIndex}_pk.json \
      --xmss-sk /config/hash-sig-keys/validator_${hashSigKeyIndex}_sk.json \
      --bootnodes /config/nodes.yaml \
      --data-dir /data \
      --node-id $item --node-key /config/$privKeyPath \
      --listen-addr /ip4/0.0.0.0/udp/$quicPort/quic-v1 \
      --prometheus-port $metricsPort"

# choose either binary or docker
node_setup="docker"
