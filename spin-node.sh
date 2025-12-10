#!/bin/bash
# set -e

currentDir=$(pwd)
scriptDir=$(dirname $0)
if [ "$scriptDir" == "." ]; then
  scriptDir="$currentDir"
fi

# 0. parse env and args
source "$(dirname $0)/parse-env.sh"

# Check if yq is installed (needed for deployment mode detection)
if ! command -v yq &> /dev/null; then
    echo "Error: yq is required but not installed. Please install yq first."
    echo "On macOS: brew install yq"
    echo "On Linux: https://github.com/mikefarah/yq#install"
    exit 1
fi

# Determine initial validator config file location
if [ "$validatorConfig" == "genesis_bootnode" ] || [ -z "$validatorConfig" ]; then
    validator_config_file="$configDir/validator-config.yaml"
else
    validator_config_file="$validatorConfig"
fi

# Read deployment mode: command-line argument takes precedence over config file
if [ -n "$deploymentMode" ]; then
    # Use command-line argument if provided
    deployment_mode="$deploymentMode"
    echo "Using deployment mode from command line: $deployment_mode"
else
    # Otherwise read from config file (default to 'local' if not specified)
    if [ -f "$validator_config_file" ]; then
        deployment_mode=$(yq eval '.deployment_mode // "local"' "$validator_config_file")
        echo "Using deployment mode from config file: $deployment_mode"
    else
        deployment_mode="local"
        echo "Using default deployment mode: $deployment_mode"
    fi
fi

# If deployment mode is ansible and no explicit validatorConfig was provided,
# switch to ansible-devnet/genesis/validator-config.yaml and update configDir/dataDir
# This must happen BEFORE set-up.sh so genesis generation uses the correct directory
if [ "$deployment_mode" == "ansible" ] && ([ "$validatorConfig" == "genesis_bootnode" ] || [ -z "$validatorConfig" ]); then
    configDir="$scriptDir/ansible-devnet/genesis"
    dataDir="$scriptDir/ansible-devnet/data"
    validator_config_file="$configDir/validator-config.yaml"
    echo "Using Ansible deployment: configDir=$configDir, validator config=$validator_config_file"
fi

#1. setup genesis params and run genesis generator
source "$(dirname $0)/set-up.sh"
# ✅ Genesis generator implemented using PK's eth-beacon-genesis tool
# Generates: validators.yaml, nodes.yaml, genesis.json, genesis.ssz, and .key files

# 2. collect the nodes that the user has asked us to spin and perform setup

# Load nodes from validator config file
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
    if [ "$deployment_mode" == "ansible" ]; then
        echo "Please create ansible-devnet/genesis/validator-config.yaml for Ansible deployments"
    fi
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

# Check deployment mode and route to ansible if needed
if [ "$deployment_mode" == "ansible" ]; then
  # Validate Ansible prerequisites before routing to Ansible deployment
  echo "Validating Ansible prerequisites..."
  
  # Check if Ansible is installed
  if ! command -v ansible-playbook &> /dev/null; then
    echo "Error: ansible-playbook is not installed."
    echo "Install Ansible:"
    echo "  macOS:   brew install ansible"
    echo "  Ubuntu:  sudo apt-get install ansible"
    echo "  pip:     pip install ansible"
    exit 1
  fi
  
  # Check if docker collection is available
  if ! ansible-galaxy collection list | grep -q "community.docker" 2>/dev/null; then
    echo "Warning: community.docker collection not found. Installing..."
    ansible-galaxy collection install community.docker
  fi
  
  echo "✅ Ansible prerequisites validated"
  
  # Call separate Ansible execution script
  # If Ansible deployment fails, exit immediately (don't fall through to local deployment)
  if ! "$scriptDir/run-ansible.sh" "$configDir" "$node" "$cleanData" "$validatorConfig" "$validator_config_file" "$sshKeyFile" "$useRoot"; then
    echo "❌ Ansible deployment failed. Exiting."
    exit 1
  fi
  
  # Ansible deployment succeeded, exit normally
  exit 0
fi

# 3. run clients (local deployment)
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
    # Extract image name from node_docker (find word containing ':' which is the image:tag)
    docker_image=$(echo "$node_docker" | grep -oE '[^ ]+:[^ ]+' | head -1)
    # Pull image first 
    if [ -n "$dockerWithSudo" ]; then
      sudo docker pull "$docker_image" || true
    else
      docker pull "$docker_image" || true
    fi
    execCmd="docker run --rm --pull=never"
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
echo -e "\n\nwaiting for nodes to exit"
printf '%*s' $(tput cols) | tr ' ' '-'
echo "press Ctrl+C to exit and cleanup..."
# Wait for background processes - use a compatible approach for all shells
if [ ${#spinned_pids[@]} -gt 0 ]; then
  for pid in "${spinned_pids[@]}"; do
    wait $pid 2>/dev/null || true
  done
else
  # Fallback: wait for any background job
  wait
fi
cleanup
