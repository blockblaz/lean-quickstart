#!/bin/bash
# set -e

currentDir=$(pwd)
scriptDir=$(dirname "$0")
if [ "$scriptDir" == "." ]; then
  scriptDir="$currentDir"
fi

# 0. parse env and args
source "$(dirname $0)/parse-env.sh"

#1. setup genesis params and run genesis generator
source "$(dirname $0)/set-up.sh"
# ✅ Genesis generator implemented using PK's eth-beacon-genesis tool
# Generates: validators.yaml, nodes.yaml, genesis.json, genesis.ssz, and .key files

# 2. collect the nodes that the user has asked us to spin and perform setup
if [ "$validatorConfig" == "genesis_bootnode" ] || [ -z "$validatorConfig" ]; then
    validator_config_file="$configDir/validator-config.yaml"
else
    validator_config_file="$validatorConfig"
fi

# Check if yq is installed
if ! command -v yq &> /dev/null; then
    echo "Error: yq is required but not installed. Please install yq first."
    echo "On macOS: brew install yq"
    echo "On Linux: https://github.com/mikefarah/yq#install"
    exit 1
fi

if [ -f "$validator_config_file" ]; then
    # Use yq to extract node names from validator config
    nodes=($(yq eval '.validators[].name' "$validator_config_file"))
    
    # Validate that we found nodes
    if [ ${#nodes[@]} -eq 0 ]; then
        echo "Error: No validators found in $validator_config_file"
        exit 1
    fi
else
    echo "Error: Validator config file not found at $validator_config_file"
    nodes=()
    exit 1
fi

echo "Detected nodes: ${nodes[@]}"
# nodes=("zeam_0" "ream_0" "qlean_0")
spin_nodes=()

# Parse comma-separated or space-separated node names or handle single node/all
if [[ "$node" == "all" ]]; then
  # Spin all nodes
  spin_nodes=("${nodes[@]}")
  node_present=true
else
  # Handle both comma-separated and space-separated node names
  if [[ "$node" == *","* ]]; then
    IFS=',' read -r -a requested_nodes <<< "$node"
  else
    IFS=' ' read -r -a requested_nodes <<< "$node"
  fi

  # Check each requested node against available nodes
  for requested_node in "${requested_nodes[@]}"; do
    node_found=false
    for available_node in "${nodes[@]}"; do
      if [[ "$requested_node" == "$available_node" ]]; then
        spin_nodes+=("$available_node")
        node_present=true
        node_found=true
        break
      fi
    done

    if [[ "$node_found" == false ]]; then
      echo "Error: Node '$requested_node' not found in validator config"
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
mkdir -p "$dataDir"

# Detect OS and set appropriate terminal command
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS requires special handling with osascript
  popupTerminalCmd="macos_terminal"
elif command -v gnome-terminal &> /dev/null; then
  # Linux with gnome-terminal
  popupTerminalCmd="gnome-terminal --"
elif command -v xterm &> /dev/null; then
  # Fallback to xterm
  popupTerminalCmd="xterm -e"
else
  # No terminal emulator found
  popupTerminalCmd=""
  echo "Warning: No supported terminal emulator found. --popupTerminal option will not work."
fi

spinned_pids=()
for item in "${spin_nodes[@]}"; do
  echo -e "\n\nspining $item: client=$client (mode=$node_setup)"
  printf '%*s' $(tput cols) | tr ' ' '-'
  echo

  # create and/or cleanup datadirs
  itemDataDir="$dataDir/$item"
  mkdir -p "$itemDataDir"
  cmd="rm -rf \"$itemDataDir\"/*"
  echo "$cmd"
  eval "$cmd"

  # parse validator-config.yaml for $item to load args values
  source "parse-vc.sh"

  # extract client config
  IFS='_' read -r -a elements <<< "$item"
  client="${elements[0]}"

  # get client specific cmd and its mode (docker, binary)
  sourceCmd="source client-cmds/$client-cmd.sh"
  echo "$sourceCmd"
  eval "$sourceCmd"

  # spin nodes
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
          -v \"$configDir\":/config \
          -v \"$dataDir/$item\":/data \
          $node_docker"
  fi;

  if [ -n "$popupTerminal" ]
  then
    if [ "$popupTerminalCmd" == "macos_terminal" ]; then
      # macOS Terminal.app requires osascript with escaped quotes
      escaped_cmd="${execCmd//\"/\\\"}"
      echo "osascript -e 'tell app \"Terminal\" to do script \"$escaped_cmd\"'"
      osascript -e "tell app \"Terminal\" to do script \"$escaped_cmd\"" &
      pid=$!
    else
      # Linux terminals
      execCmd="$popupTerminalCmd $execCmd"
      echo "$execCmd"
      eval "$execCmd" &
      pid=$!
    fi
  else
    echo "$execCmd"
    eval "$execCmd" &
    pid=$!
  fi

  # Only track PIDs when not using popup terminal
  # (popup terminals spawn separate processes we can't track)
  if [ -z "$popupTerminal" ]; then
    spinned_pids+=("$pid")
  fi
done;

container_names="${spin_nodes[*]}"
process_ids="${spinned_pids[*]}"

cleanup() {
  echo -e "\n\ncleaning up"
  printf '%*s' $(tput cols) | tr ' ' '-'
  echo

  # try for docker containers
  if [ -n "$container_names" ]; then
    execCmd="docker rm -f $container_names"
    if [ -n "$dockerWithSudo" ]
      then
        execCmd="sudo $execCmd"
    fi;
    echo "$execCmd"
    eval "$execCmd" 2>/dev/null || echo "Note: Some containers may have already stopped"
  fi

  # try for process ids
  if [ -n "$process_ids" ]; then
    execCmd="kill -9 $process_ids"
    echo "$execCmd"
    eval "$execCmd" 2>/dev/null || echo "Note: Some processes may have already exited"
  fi
}

trap "echo exit signal received;cleanup" SIGINT SIGTERM
echo -e "\n\nwaiting for nodes to exit"
printf '%*s' $(tput cols) | tr ' ' '-'
echo "press Ctrl+C to exit and cleanup..."

# Wait for any process to exit
# Compatible with bash 3.2 (macOS) which doesn't support wait -n
if [ ${#spinned_pids[@]} -gt 0 ]; then
  # We have PIDs to wait on (non-popup terminal mode)
  while true; do
    for pid in "${spinned_pids[@]}"; do
      if ! kill -0 "$pid" 2>/dev/null; then
        # Process has exited
        break 2
      fi
    done
    sleep 0.1
  done
else
  # Popup terminal mode - just wait for Ctrl+C
  echo "(Running in popup terminal mode - monitoring containers...)"
  while true; do
    # Check if any containers are still running
    if [ -n "$container_names" ]; then
      running_count=0
      for container in ${spin_nodes[@]}; do
        if docker ps -q -f name="$container" 2>/dev/null | grep -q .; then
          running_count=$((running_count + 1))
        fi
      done
      if [ $running_count -eq 0 ]; then
        echo "All containers have stopped"
        break
      fi
    fi
    sleep 1
  done
fi

cleanup
