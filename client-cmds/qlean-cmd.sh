#!/bin/bash

#-----------------------qlean setup----------------------
# expects "qlean" submodule or symlink inside "lean-quickstart" root directory
# https://github.com/qdrvm/qlean-mini
node_binary="$scriptDir/qlean/build/src/executable/qlean \
      --modules-dir $scriptDir/qlean/build/src/modules \
      --genesis $configDir/config.yaml \
      --validator-registry-path $configDir/validators.yaml \
      --bootnodes $configDir/nodes.yaml \
      --data-dir $dataDir/$item \
      --node-id $item --node-key $configDir/$privKeyPath \
      --listen-addr /ip4/0.0.0.0/udp/$quicPort/quic-v1"

node_docker="--platform linux/amd64 qdrvm/qlean-mini:3f121fc \
      --genesis /config/config.yaml \
      --validator-registry-path /config/validators.yaml \
      --bootnodes /config/nodes.yaml \
      --data-dir /data \
      --node-id $item --node-key /config/$privKeyPath \
      --listen-addr /ip4/0.0.0.0/udp/$quicPort/quic-v1"

# choose either binary or docker
node_setup="docker"
