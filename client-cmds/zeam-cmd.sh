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

# TODO: Remove --platform linux/amd64 when blockblaz/zeam:latest multi-platform image is available on Docker Hub
# Multi-platform support is being added in zeam CI (see .github/workflows/ci.yml docker-build-multiarch job)
ZEAM_TAG="${dockerTag:-latest}"
node_docker="--platform linux/amd64 --security-opt seccomp=unconfined blockblaz/zeam:${ZEAM_TAG} node \
      --custom_genesis /config \
      --validator_config $validatorConfig \
      --data-dir /data \
      --node-id $item --node-key /config/$item.key \
      --metrics_port $metricsPort"

# choose either binary or docker
node_setup="docker"