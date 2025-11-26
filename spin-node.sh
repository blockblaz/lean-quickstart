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
mkdir -p $dataDir
# Detect OS and set appropriate terminal command
popupTerminalCmd=""
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS - don't use popup terminal by default, just run in background
  popupTerminalCmd=""
elif [[ "$OSTYPE" == "linux"* ]]; then
  # Linux try a list of common terminals in order of preference
  for term in x-terminal-emulator gnome-terminal konsole xfce4-terminal kitty alacritty lxterminal lxqt-terminal mate-terminal terminator xterm; do
    if command -v "$term" &>/dev/null; then
      # Most terminals accept `--` as "end of options" before the command
      case "$term" in
        gnome-terminal|xfce4-terminal|konsole|lxterminal|lxqt-terminal|terminator|alacritty|kitty)
          popupTerminalCmd="$term --"
          ;;
        xterm|mate-terminal|x-terminal-emulator)
          popupTerminalCmd="$term -e"
          ;;
        *)
          popupTerminalCmd="$term"
          ;;
      esac
      break
    fi
  done
fi
spinned_pids=()
for item in "${spin_nodes[@]}"; do
  echo -e "\n\nspining $item: client=$client (mode=$node_setup)"
  printf '%*s' $(tput cols) | tr ' ' '-'
  echo

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
  if [ "$node_setup" == "binary" ]
  then
    execCmd="$node_binary"
  else
    # Extract image name from node_docker to check if it's a local image
    # Local images don't have a registry prefix (no "/")
    # Remote images (like "blockblaz/zeam:devnet1" or "ghcr.io/reamlabs/ream:latest") have a registry prefix
    # The image name is typically the first word that looks like an image (contains ":" or is followed by a command)
    if echo "$node_docker" | grep -qE '(blockblaz|ghcr\.io|docker\.io|quay\.io)/'; then
      # Remote image - use --pull=always and force linux/amd64 platform
      pull_flag="--pull=always"
      platform_flag="--platform=linux/amd64"
    else
      # Local image - explicitly don't pull, use native platform
      pull_flag="--pull=never"
      platform_flag=""
    fi
    
    # Build docker run command
    execCmd="docker run --rm $pull_flag $platform_flag"
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
  echo -e "\n\ncleaning up"
  printf '%*s' $(tput cols) | tr ' ' '-'
  echo

  # Stop and remove docker containers (containers are the primary thing to stop)
  if [ -n "$container_names" ]; then
    # First try to stop containers gracefully with a timeout
    for container in $container_names; do
      stopCmd="docker stop -t 5 $container"
      if [ -n "$dockerWithSudo" ]; then
        stopCmd="sudo $stopCmd"
      fi
      echo "$stopCmd"
      eval "$stopCmd" 2>/dev/null || true
    done
    
    # Then force remove containers
    execCmd="docker rm -f $container_names"
    if [ -n "$dockerWithSudo" ]; then
      execCmd="sudo $execCmd"
    fi
    echo "$execCmd"
    eval "$execCmd" 2>/dev/null || true
  fi

  # Kill background processes (these are just the docker run commands, containers are already stopped)
  if [ -n "$process_ids" ]; then
    execCmd="kill -TERM $process_ids 2>/dev/null || true"
    echo "$execCmd"
    eval "$execCmd"
    sleep 0.5
    # Force kill if still running
    execCmd="kill -9 $process_ids 2>/dev/null || true"
    echo "$execCmd"
    eval "$execCmd"
  fi
}

cleanup_and_exit() {
  cleanup
  exit 0
}

trap cleanup_and_exit SIGINT SIGTERM
echo -e "\n\nwaiting for nodes to exit"
printf '%*s' $(tput cols) | tr ' ' '-'
echo "press Ctrl+C to exit and cleanup..."
# Wait for background processes - use a polling approach that's interruptible
if [ ${#spinned_pids[@]} -gt 0 ]; then
  while true; do
    all_done=true
    for pid in "${spinned_pids[@]}"; do
      if kill -0 $pid 2>/dev/null; then
        all_done=false
        break
      fi
    done
    if [ "$all_done" = true ]; then
      break
    fi
    # Sleep briefly to allow signals to be processed
    sleep 0.5
  done
else
  # Fallback: wait for any background job (this can block, but it's a fallback)
  wait
fi
cleanup
