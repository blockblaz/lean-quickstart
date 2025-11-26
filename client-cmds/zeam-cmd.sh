#!/bin/bash

#-----------------------zeam setup----------------------
# setup where lean-quickstart is a submodule folder in zeam repo
# update the path to your binary here if you want to use binary
node_binary="$scriptDir/../zig-out/bin/zeam node \
      --custom_genesis $configDir \
      --validator_config $validatorConfig \
      --data-dir $dataDir/$item \
      --node-id $item --node-key $configDir/$item.key \
      --metrics_port $metricsPort"

# Use Zeam docker image (default: blockblaz/zeam:devnet1)
# To use a local image, set ZEAM_DOCKER_IMAGE environment variable
ZEAM_DOCKER_IMAGE="${ZEAM_DOCKER_IMAGE:-blockblaz/zeam:devnet1}"
node_docker="--security-opt seccomp=unconfined $ZEAM_DOCKER_IMAGE node \
      --custom_genesis /config \
      --validator_config $validatorConfig \
      --data-dir /data \
      --node-id $item --node-key /config/$item.key \
      --metrics_port $metricsPort"

# choose either binary or docker
node_setup="docker"