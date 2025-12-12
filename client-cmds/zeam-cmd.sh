#!/bin/bash

#-----------------------zeam setup----------------------
# setup where lean-quickstart is a submodule folder in zeam repo
# update the path to your binary here if you want to use binary
# Metrics enabled by default
metrics_flag="--metrics_enable"

node_binary="$scriptDir/../zig-out/bin/zeam node \
      --custom_genesis $configDir \
      --validator_config $validatorConfig \
      --data-dir $dataDir/$item \
      --node-id $item --node-key $configDir/$item.key \
      $metrics_flag \
      --metrics_port $metricsPort"

node_docker="--security-opt seccomp=unconfined blockblaz/zeam:devnet1 node \
      --custom_genesis /config \
      --validator_config $validatorConfig \
      --data-dir /data \
      --node-id $item --node-key /config/$item.key \
      $metrics_flag \
      --metrics_port $metricsPort"

# choose either binary or docker
node_setup="docker"
