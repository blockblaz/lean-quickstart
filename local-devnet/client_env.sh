#!/bin/bash
# set -e

# ideally read config from validatorConfig and figure out all nodes in the array
# if validatorConfig is genesis bootnode then we read the genesis/validator_config.yaml for this
# please note that the clients are infered from the name of the nodes
nodes=("zeam_0" "ream_0")

# ---------------------------------------------------------------------------------------------
# the client binary or docker setup configuration for this devnet
# 1. code & activate  for your client
# 2. binary requires one standard arg: --data_dir to specify data dir at the
#    command run time
# 2. docker containers are to be run on network host so that port mappings
#    in validator_config.yaml can be directly applied. the following will be
#    standard mounted volumes:
#      a) genesis folder will be mounted at /config
#      b) dataDir for this node will be mounted at /data
# 3. node_key arg is to be a standard arg to look for that particular node config
#    and will be attached while running the actual command so assume that arg will
#    be appeneded in the end

#-----------------------zeam setup----------------------
# setup where lean-quickstart is a submodule folder in zeam repo
# update the path to your binary here if you want to use binary
zeam_BINARY_REF="$scriptDir/../zig-out/bin/zeam node \
      --custom_genesis $configDir \
      --validator_config $validatorConfig"
zeam_DOCKER_REF="--security-opt seccomp=unconfined g11tech/zeam:latest node \
      --custom_genesis /config \
      --data-dir /data \
      --validator_config $validatorConfig"
# choose either binary or docker
zeam_setup="docker"

#-----------------------ream setup----------------------
ream_BINARY_REF=
ream_DOCKER_REF=
ream_setup="docker"

#-----------------------qlean setup----------------------
qlean_BINARY_REF=
qlean_DOCKER_REF=
qlean_setup="docker"
