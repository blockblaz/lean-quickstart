#!/bin/bash
# set -e

currentDir=$(pwd)
scriptDir=$(dirname $0)

# 0. parse env and args
source "$(dirname $0)/parse-env.sh"

#1. setup genesis params and run genesis generator
source "$(dirname $0)/set-up.sh"
#  TODO: run genesis generator
# should take config.yaml and validator-config.yaml and generate files
# 1. nodes.yaml 2. validators.yaml 3. .key files for each of nodes

# 2. get the client cmds with args set
source "$scriptDir/$NETWORK_DIR/client_env.sh"

# 3. collect the nodes that the user has asked us to spin and perform setup
spin_nodes=()
for item in "${nodes[@]}"; do
  if [ $node == $item ] || [ $node == "all" ]
  then
    node_present=true
    spin_nodes+=($item)
  fi;
done
if [ ! -n "$node_present" ] && [ node != "all" ]
then
  echo "invalid specified node, options =${nodes[@]} all, exiting."
  exit;
fi;

# 4. run clients
mkdir $dataDir
popupTerminalCmd="gnome-terminal --disable-factory --"
for item in "${spin_nodes[@]}"; do
  # create and/or cleanup datadirs
  itemDataDir="$dataDir/$item"
  mkdir $itemDataDir
  cmd="sudo rm -rf $itemDataDir/*"
  echo $cmd
  eval $cmd

  # extract client config
  IFS='_' read -r -a elements <<< "$item"
  client="${elements[0]}"

  setup_var_name="${client}_setup"
  node_setup="${!setup_var_name}"

  binary_var_name="${client}_BINARY_REF"
  node_binary="${!binary_var_name}"

  docker_var_name="${client}_DOCKER_REF"
  node_docker="${!docker_var_name}"

  # spin nodes
  echo -e "\n\nspining $item: client=$client (mode=$node_setup)"
  printf '%*s' $(tput cols) | tr ' ' '-'
  echo

  if [ "$node_setup" == "binary" ]
  then
    execCmd="$node_binary \
      --data-dir $dataDir/$item \
      --node-id $item --node-key $configDir/$item.key"
  else
    execCmd="docker run --rm"
    if [ -n "$dockerWithSudo" ]
    then
      execCmd="sudo $execCmd"
    fi;

    execCmd="$execCmd --name $item --network host -v $configDir:/config -v $dataDir/$item:/data $node_docker \
      --node-id $item --node-key /config/$item.key"
  fi;

  if [ -n "$popupTerminal" ]
  then
    execCmd="$popupTerminalCmd $execCmd"
  fi;

  echo "$execCmd"
  eval "$execCmd" &
done;
