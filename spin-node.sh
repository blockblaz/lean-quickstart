#!/bin/bash
# set -e

currentDir=$(pwd)
scriptDir=$(dirname $0)

# 1. parse env and args
source "$(dirname $0)/parse-env.sh"
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
source "$(dirname $0)/set-up.sh"

# 4. run clients
popupTerminal="gnome-terminal --disable-factory --"
for item in "${spin_nodes[@]}"; do
  # extract client config
  IFS='_' read -r -a elements <<< "$item"
  client="${elements[0]}"

  setup_var_name="${client}_setup"
  node_setup="${!setup_var_name}"

  binary_var_name="${client}_BINARY_REF"
  node_binary="${!binary_var_name}"

  docker_var_name="${client}_DOCKER_REF"
  node_docker="${!docker_var_name}"

  echo -e "\n\nspining $item: client=$client (mode=$node_setup)"
  printf '%*s' $(tput cols) | tr ' ' '-'
  echo

  if [ "$node_setup" == "binary" ]
  then
    execCmd="$node_binary \
      --data_dir $dataDir/$item \
      --node_key $item"
  else
    execCmd="docker run --rm"
    if [ -n "$dockerWithSudo" ]
    then
      execCmd="sudo $execCmd"
    fi;

    execCmd="$execCmd --name $item --network host -v $configDir:/config -v $dataDir/$item:/data $node_docker \
      --node_key $item"
  fi;

  if [ ! -n "$inTerminal" ]
  then
    execCmd="$popupTerminal $execCmd"
  fi;

  echo "$execCmd"
  eval "$execCmd" &
done;