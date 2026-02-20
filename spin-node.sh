#!/bin/bash
# set -e

currentDir=$(pwd)
scriptDir=$(dirname $0)
if [ "$scriptDir" == "." ]; then
  scriptDir="$currentDir"
fi

# 0. parse env and args
source "$(dirname $0)/parse-env.sh"

# Helper function to check if core dumps should be enabled for a node
# Accepts: "all", exact node names (zeam_0), or client types (zeam)
should_enable_core_dumps() {
  local node_name="$1"
  local client_type="${node_name%%_*}"  # Extract client type (e.g., "zeam" from "zeam_0")

  [ -z "$coreDumps" ] && return 1
  [ "$coreDumps" = "all" ] && return 0

  IFS=',' read -r -a dump_targets <<< "$coreDumps"
  for target in "${dump_targets[@]}"; do
    # Exact node name match or client type match
    [ "$target" = "$node_name" ] || [ "$target" = "$client_type" ] && return 0
  done
  return 1
}

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
restart_with_checkpoint_sync=false

# When --restart-client is specified, use it as the node list and enable checkpoint sync mode
if [[ -n "$restartClient" ]]; then
  echo "Note: --restart-client is only used with --checkpoint-sync-url (default: https://leanpoint.leanroadmap.org/lean/v0/states/finalized)"
  restart_with_checkpoint_sync=true
  # Skip genesis when restarting with checkpoint sync (we're syncing from remote)
  generateGenesis=false
  # Parse comma-separated client names
  IFS=',' read -r -a requested_nodes <<< "$restartClient"
  for requested_node in "${requested_nodes[@]}"; do
    requested_node=$(echo "$requested_node" | xargs)  # trim whitespace
    node_found=false
    for available_node in "${nodes[@]}"; do
      if [[ "$requested_node" == "$available_node" ]]; then
        spin_nodes+=("$available_node")
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
  echo "Restarting with checkpoint sync: ${spin_nodes[*]} from $checkpointSyncUrl"
  cleanData=true  # Clear data when restarting with checkpoint sync
  node_present=true
# Parse comma-separated or space-separated node names or handle single node/all
elif [[ "$node" == "all" ]]; then
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
  
  # Determine node list for Ansible: use restartClient/spin_nodes when restarting, else $node
  if [[ "$restart_with_checkpoint_sync" == "true" ]]; then
    ansible_node_arg=$(IFS=','; echo "${spin_nodes[*]}")
  else
    ansible_node_arg="$node"
  fi

  # Determine skip_genesis for Ansible (true when restarting with checkpoint sync)
  ansible_skip_genesis="false"
  [[ "$restart_with_checkpoint_sync" == "true" ]] && ansible_skip_genesis="true"

  # Handle stop action
  if [ -n "$stopNodes" ] && [ "$stopNodes" == "true" ]; then
    echo "Stopping nodes via Ansible..."
    if ! "$scriptDir/run-ansible.sh" "$configDir" "$ansible_node_arg" "$cleanData" "$validatorConfig" "$validator_config_file" "$sshKeyFile" "$useRoot" "stop" "$coreDumps" "$ansible_skip_genesis"; then
      echo "❌ Ansible stop operation failed. Exiting."
      exit 1
    fi
    exit 0
  fi
  
  # Call separate Ansible execution script
  # If Ansible deployment fails, exit immediately (don't fall through to local deployment)
  if ! "$scriptDir/run-ansible.sh" "$configDir" "$ansible_node_arg" "$cleanData" "$validatorConfig" "$validator_config_file" "$sshKeyFile" "$useRoot" "" "$coreDumps" "$ansible_skip_genesis"; then
    echo "❌ Ansible deployment failed. Exiting."
    exit 1
  fi
  
  # Ansible deployment succeeded, exit normally
  exit 0
fi

# Handle stop action for local deployment
if [ -n "$stopNodes" ] && [ "$stopNodes" == "true" ]; then
  echo "Stopping local nodes..."
  
  # Load nodes from validator config file
  if [ -f "$validator_config_file" ]; then
    nodes=($(yq eval '.validators[].name' "$validator_config_file"))
  else
    echo "Error: Validator config file not found at $validator_config_file"
    exit 1
  fi
  
  # Determine which nodes to stop
  if [[ "$node" == "all" ]]; then
    stop_nodes=("${nodes[@]}")
  else
    if [[ "$node" == *","* ]]; then
      IFS=',' read -r -a requested_nodes <<< "$node"
    else
      IFS=' ' read -r -a requested_nodes <<< "$node"
    fi
    stop_nodes=("${requested_nodes[@]}")
  fi
  
  # Stop Docker containers
  for node_name in "${stop_nodes[@]}"; do
    echo "Stopping $node_name..."
    if [ -n "$dockerWithSudo" ]; then
      sudo docker rm -f "$node_name" 2>/dev/null || echo "  Container $node_name not found or already stopped"
    else
      docker rm -f "$node_name" 2>/dev/null || echo "  Container $node_name not found or already stopped"
    fi
  done
  
  # Stop metrics stack if --metrics flag was passed
  if [ -n "$enableMetrics" ] && [ "$enableMetrics" == "true" ]; then
    echo "Stopping metrics stack..."
    metricsDir="$scriptDir/metrics"
    if [ -n "$dockerWithSudo" ]; then
      sudo docker compose -f "$metricsDir/docker-compose-metrics.yaml" down 2>/dev/null || echo "  Metrics stack not running or already stopped"
    else
      docker compose -f "$metricsDir/docker-compose-metrics.yaml" down 2>/dev/null || echo "  Metrics stack not running or already stopped"
    fi
  fi

  echo "✅ Local nodes stopped successfully!"
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

  # When restarting with checkpoint sync, stop existing container first
  if [[ "$restart_with_checkpoint_sync" == "true" ]]; then
    echo "Stopping existing container $item..."
    if [ -n "$dockerWithSudo" ]; then
      sudo docker rm -f "$item" 2>/dev/null || true
    else
      docker rm -f "$item" 2>/dev/null || true
    fi
  fi

  # create and/or cleanup datadirs
  itemDataDir="$dataDir/$item"
  mkdir -p $itemDataDir
  if [ -n "$cleanData" ]; then
    cmd="rm -rf \"$itemDataDir\"/*"
    if [ -n "$dockerWithSudo" ]; then
      cmd="sudo $cmd"
    fi
    echo "$cmd"
    eval "$cmd"
  fi

  # parse validator-config.yaml for $item to load args values
  source parse-vc.sh

  # export checkpoint_sync_url for client-cmd scripts when restarting with checkpoint sync
  if [[ "$restart_with_checkpoint_sync" == "true" ]] && [[ -n "$checkpointSyncUrl" ]]; then
    export checkpoint_sync_url="$checkpointSyncUrl"
  else
    unset checkpoint_sync_url 2>/dev/null || true
  fi

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
    # Add core dump support if enabled for this node
    if should_enable_core_dumps "$item"; then
      execCmd="ulimit -c unlimited && $node_binary"
      echo "Core dumps enabled for $item (binary mode)"
    else
      execCmd="$node_binary"
    fi
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

    # Use --network host for peer-to-peer communication to work
    # On macOS Docker Desktop, containers share the VM's network stack, allowing them
    # to reach each other via 127.0.0.1 (as configured in nodes.yaml ENR records).
    # Note: Port mapping (-p) doesn't work with --network host, so metrics endpoints
    # are not directly accessible from the macOS host. Use 'docker exec' to access them.

    # Add core dump support if enabled for this node
    # --init: forwards signals and reaps zombies (required for core dumps)
    # --workdir /data: dumps land in the mounted volume
    if should_enable_core_dumps "$item"; then
      execCmd="$execCmd --init --ulimit core=-1 --workdir /data"
      echo "Core dumps enabled for $item (dumps will be written to $dataDir/$item/)"
    fi

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

# 4. Start metrics stack (Prometheus + Grafana) if --metrics flag was passed
if [ -n "$enableMetrics" ] && [ "$enableMetrics" == "true" ]; then
  echo -e "\n\nStarting metrics stack (Prometheus + Grafana)..."
  printf '%*s' $(tput cols) | tr ' ' '-'
  echo

  metricsDir="$scriptDir/metrics"

  # Generate prometheus.yml from validator-config.yaml
  "$scriptDir/generate-prometheus-config.sh" "$validator_config_file" "$metricsDir/prometheus"

  # Pull and start metrics containers
  if [ -n "$dockerWithSudo" ]; then
    sudo docker compose -f "$metricsDir/docker-compose-metrics.yaml" up -d
  else
    docker compose -f "$metricsDir/docker-compose-metrics.yaml" up -d
  fi

  echo ""
  echo "📊 Metrics stack started:"
  echo "   Prometheus: http://localhost:9090"
  echo "   Grafana:    http://localhost:3000"
  echo ""
fi

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

  # Stop metrics stack if it was started
  if [ -n "$enableMetrics" ] && [ "$enableMetrics" == "true" ]; then
    echo "Stopping metrics stack..."
    metricsDir="$scriptDir/metrics"
    if [ -n "$dockerWithSudo" ]; then
      sudo docker compose -f "$metricsDir/docker-compose-metrics.yaml" down 2>/dev/null || true
    else
      docker compose -f "$metricsDir/docker-compose-metrics.yaml" down 2>/dev/null || true
    fi
  fi
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
