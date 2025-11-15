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
    
    # Check deployment mode: command-line argument takes precedence over config file
    if [ -n "$deploymentMode" ]; then
        # Use command-line argument if provided
        deployment_mode="$deploymentMode"
        echo "Using deployment mode from command line: $deployment_mode"
    else
        # Otherwise read from config file (default to 'local' if not specified)
        deployment_mode=$(yq eval '.deployment_mode // "local"' "$validator_config_file")
        echo "Using deployment mode from config file: $deployment_mode"
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

# Check deployment mode and route to ansible if needed
if [ "$deployment_mode" == "ansible" ]; then
  echo "Deployment mode: ansible - routing to Ansible deployment"
  
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
  
  # Generate ansible inventory from validator-config.yaml
  ANSIBLE_DIR="$scriptDir/ansible"
  INVENTORY_FILE="$ANSIBLE_DIR/inventory/hosts.yml"
  
  # Generate inventory if it doesn't exist or if validator config is newer
  if [ ! -f "$INVENTORY_FILE" ] || [ "$validator_config_file" -nt "$INVENTORY_FILE" ]; then
    echo "Generating Ansible inventory from validator-config.yaml..."
    "$scriptDir/generate-ansible-inventory.sh" "$validator_config_file" "$INVENTORY_FILE"
  fi
  
  # Build ansible extra-vars from spin-node.sh arguments
  EXTRA_VARS="network_dir=$configDir"
  
  if [ -n "$node" ]; then
    EXTRA_VARS="$EXTRA_VARS node_names=$node"
  fi
  
  if [ -n "$generateGenesis" ]; then
    EXTRA_VARS="$EXTRA_VARS generate_genesis=true"
  fi
  
  if [ -n "$cleanData" ]; then
    EXTRA_VARS="$EXTRA_VARS clean_data=true"
  fi
  
  if [ -n "$validatorConfig" ] && [ "$validatorConfig" != "genesis_bootnode" ]; then
    EXTRA_VARS="$EXTRA_VARS validator_config=$validatorConfig"
  fi
  
  # Determine deployment mode (docker/binary) - default to docker for ansible
  # Note: node_setup is not set yet in ansible mode, so we default to docker
  # This can be overridden by adding a 'deployment_mode' field per node in validator-config.yaml if needed
  EXTRA_VARS="$EXTRA_VARS deployment_mode=docker"
  
  # Build ansible-playbook command
  ANSIBLE_CMD="ansible-playbook"
  ANSIBLE_CMD="$ANSIBLE_CMD -i $INVENTORY_FILE"
  ANSIBLE_CMD="$ANSIBLE_CMD $ANSIBLE_DIR/playbooks/site.yml"
  ANSIBLE_CMD="$ANSIBLE_CMD -e \"$EXTRA_VARS\""
  
  echo "Running Ansible playbook..."
  echo "Command: $ANSIBLE_CMD"
  echo ""
  
  # Change to Ansible directory and execute
  cd "$ANSIBLE_DIR"
  eval $ANSIBLE_CMD
  
  EXIT_CODE=$?
  if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "✅ Ansible deployment completed successfully!"
  else
    echo ""
    echo "❌ Ansible deployment failed with exit code $EXIT_CODE"
    exit $EXIT_CODE
  fi
  
  # Exit early - ansible handles everything
  exit $EXIT_CODE
fi

# 3. run clients (local deployment)
mkdir -p $dataDir
# Detect OS and set appropriate terminal command
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS - don't use popup terminal by default, just run in background
  popupTerminalCmd=""
elif command -v gnome-terminal &> /dev/null; then
  # Linux with gnome-terminal
  popupTerminalCmd="gnome-terminal --disable-factory --"
else
  # Fallback for other systems
  popupTerminalCmd=""
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
