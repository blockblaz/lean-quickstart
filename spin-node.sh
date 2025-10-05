#!/bin/bash
# set -e

currentDir=$(pwd)
scriptDir=$(dirname $0)
if [ "$scriptDir" == "." ]; then
  scriptDir="$currentDir"
fi

# 0. parse env and args
source "$(dirname $0)/parse-env.sh"

#1. setup genesis params and run genesis generator
source "$(dirname $0)/set-up.sh"
#  TODO: run genesis generator
# should take config.yaml and validator-config.yaml and generate files
# 1. nodes.yaml 2. validators.yaml 3. .key files for each of nodes

# 2. collect the nodes that the user has asked us to spin and perform setup
if [ "$validatorConfig" == "genesis_bootnode" ] || [ -z "$validatorConfig" ]; then
    validator_config_file="$configDir/validator-config.yaml"
else
    validator_config_file="$validatorConfig"
fi

if [ -f "$validator_config_file" ]; then
    nodes=($(grep -A 1 "^\s*-\s*name:" "$validator_config_file" | grep "name:" | sed 's/.*name:\s*"\(.*\)".*/\1/'))
else
    echo "Error: Validator config file not found at $validator_config_file"
    nodes=()
fi

echo "Detected nodes: ${nodes[@]}"
# nodes=("zeam_0" "ream_0" "qlean_0")
spin_nodes=()

# Parse comma-separated node names or handle single node/all
if [ $node == "all" ]; then
  # Spin all nodes
  spin_nodes=("${nodes[@]}")
  node_present=true
else
  # Split by comma to handle comma-separated node names
  IFS=',' read -r -a requested_nodes <<< "$node"

  # Check each requested node against available nodes
  for requested in "${requested_nodes[@]}"; do
    found=false
    for item in "${nodes[@]}"; do
      if [ "$requested" == "$item" ]; then
        spin_nodes+=("$item")
        node_present=true
        found=true
        break
      fi
    done

    if [ "$found" == false ]; then
      echo "Error: Node '$requested' not found in validator config"
      echo "Available nodes: ${nodes[@]}"
      exit 1
    fi
  done
fi

if [ ! -n "$node_present" ]; then
  echo "invalid specified node, options =${nodes[@]} all, exiting."
  exit;
fi;

# 3. run clients
mkdir -p $dataDir
# popupTerminalCmd="gnome-terminal --disable-factory --"
popupTerminalCmd="gnome-terminal --"
spinned_pids=()
for item in "${spin_nodes[@]}"; do
  # create and/or cleanup datadirs
  itemDataDir="$dataDir/$item"
  mkdir -p $itemDataDir
  cmd="sudo rm -rf $itemDataDir/*"
  echo $cmd
  eval $cmd

  # parse validator-config.yaml for $item to load args values
  source parse-vc.sh

  # extract client config
  IFS='_' read -r -a elements <<< "$item"
  client="${elements[0]}"

  # get client specific cmd and its mode (docker, binary)
  sourceCmd="source client-cmds/$client-cmd.sh"
  echo "$sourceCmd"
  eval $sourceCmd

  # spin nodes
  echo -e "\n\nspining $item: client=$client (mode=$node_setup)"
  printf '%*s' $(tput cols) | tr ' ' '-'
  echo


  if [ "$node_setup" == "binary" ]
  then
    execCmd="$node_binary"
  else
    execCmd="docker run --rm"
    if [ -n "$dockerWithSudo" ]
    then
      execCmd="sudo $execCmd"
    fi;

    execCmd="$execCmd --name $item --network host \
          -v $configDir:/config \
          -v $dataDir/$item:/data \
          $node_docker"
  fi;

  if [ -n "$popupTerminal" ]
  then
    execCmd="$popupTerminalCmd $execCmd"
  fi;

  echo "$execCmd"
  eval "$execCmd" &
  pid=$!
  spinned_pids+=($pid)
done;

container_names="${spin_nodes[*]}"
process_ids="${spinned_pids[*]}"

cleanup() {
  echo "cleaning up"

  # try for docker containers
  execCmd="docker rm -f $container_names"
  if [ -n "$dockerWithSudo" ]
    then
      execCmd="sudo $execCmd"
  fi;
  echo "$execCmd"
  eval "$execCmd"

  # try for process ids
  execCmd="kill -9 $process_ids"
  echo "$execCmd"
  eval "$execCmd"
}

trap "echo exit signal received;cleanup" SIGINT SIGTERM
echo "waiting for nodes to exit"
echo "press Ctrl+C to exit and cleanup..."
wait -n $process_ids
cleanup
