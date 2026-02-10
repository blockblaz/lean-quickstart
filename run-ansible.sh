#!/bin/bash
# run-ansible.sh: Execute Ansible deployment for Lean nodes
# This script handles all Ansible-related deployment logic

set -e

# Script directory - resolve to absolute path
# This handles both direct execution and execution via relative/absolute paths
scriptPath="$0"
if [ -L "$scriptPath" ]; then
  # If script is a symlink, resolve it
  scriptPath=$(readlink "$scriptPath")
  if [ "${scriptPath:0:1}" != "/" ]; then
    scriptPath="$(dirname "$0")/$scriptPath"
  fi
fi
# Get absolute path of script directory
scriptDir=$(cd "$(dirname "$scriptPath")" && pwd)

# Parse arguments
configDir="$1"
node="$2"
cleanData="$3"
validatorConfig="$4"
deploy_validator_config_file="$5"  # deploy-validator-config.yaml (with user overrides merged)
sshKeyFile="$6"
useRoot="$7"  # Flag to use root user (defaults to current user)
action="$8"   # Action: "stop" to stop nodes, otherwise deploy

# Determine SSH user: use root if --useRoot flag is set, otherwise use current user
if [ "$useRoot" == "true" ]; then
  sshUser="root"
else
  sshUser=$(whoami)  # Use current user
fi

# Validate required arguments
if [ -z "$configDir" ] || [ -z "$deploy_validator_config_file" ]; then
  echo "Error: Missing required arguments"
  echo "Usage: $0 <configDir> <node> <cleanData> <validatorConfig> <deploy_validator_config_file> [sshKeyFile] [useRoot] [action]"
  exit 1
fi

echo "Deployment mode: ansible - routing to Ansible deployment"
echo "SSH user for remote connections: $sshUser"
# Note: Ansible prerequisites are validated in spin-node.sh before calling this script

# Generate ansible inventory from validator-config.yaml
ANSIBLE_DIR="$scriptDir/ansible"
INVENTORY_FILE="$ANSIBLE_DIR/inventory/hosts.yml"

# Generate inventory if it doesn't exist or if deploy-validator-config.yaml is newer
if [ ! -f "$INVENTORY_FILE" ] || [ "$deploy_validator_config_file" -nt "$INVENTORY_FILE" ]; then
  echo "Generating Ansible inventory from deploy-validator-config.yaml..."
  "$scriptDir/generate-ansible-inventory.sh" "$deploy_validator_config_file" "$INVENTORY_FILE"
fi

# Update inventory with SSH key file and user if provided
if command -v yq &> /dev/null; then
  # Get all remote host groups (zeam_nodes, ream_nodes, qlean_nodes, lantern_nodes, lighthouse_nodes)
  for group in zeam_nodes ream_nodes qlean_nodes lantern_nodes lighthouse_nodes grandine_nodes ethlambda_nodes; do
    # Get all hosts in this group
    hosts=$(yq eval ".all.children.$group.hosts | keys | .[]" "$INVENTORY_FILE" 2>/dev/null || echo "")
    for host in $hosts; do
      # Only update if it's a remote host (has ansible_host but not ansible_connection: local)
      connection=$(yq eval ".all.children.$group.hosts.$host.ansible_connection // \"\"" "$INVENTORY_FILE" 2>/dev/null)
      if [ -z "$connection" ] || [ "$connection" != "local" ]; then
        # Set SSH user (defaults to current user, or root if --useRoot flag is set)
        yq eval -i ".all.children.$group.hosts.$host.ansible_user = \"$sshUser\"" "$INVENTORY_FILE"
        
        # Set SSH key file if provided
        if [ -n "$sshKeyFile" ]; then
          # Expand ~ to home directory if needed
          if [[ "$sshKeyFile" == ~* ]]; then
            sshKeyFile="${sshKeyFile/#\~/$HOME}"
          fi
          yq eval -i ".all.children.$group.hosts.$host.ansible_ssh_private_key_file = \"$sshKeyFile\"" "$INVENTORY_FILE"
          echo "Setting SSH private key file for $host: $sshKeyFile"
        fi
      fi
    done
  done
else
  echo "Warning: yq not found, cannot update inventory with SSH user/key file"
fi

# Build ansible extra-vars from spin-node.sh arguments
# configDir is already the genesis directory, so we need to get the parent for network_dir
# or pass genesis_dir directly. Since group_vars expects network_dir, we'll derive it.
# If configDir ends with /genesis, use parent; otherwise assume configDir is network_dir
if [[ "$configDir" == */genesis ]]; then
  network_dir=$(dirname "$configDir")
else
  network_dir="$configDir"
fi
EXTRA_VARS="network_dir=$network_dir"

if [ -n "$node" ]; then
  EXTRA_VARS="$EXTRA_VARS node_names=$node"
fi

if [ -n "$cleanData" ]; then
  EXTRA_VARS="$EXTRA_VARS clean_data=true"
fi

if [ -n "$validatorConfig" ] && [ "$validatorConfig" != "genesis_bootnode" ]; then
  EXTRA_VARS="$EXTRA_VARS validator_config=$validatorConfig"
fi

# Determine deployment mode (docker/binary) - read default from group_vars/all.yml
# Default to 'docker' if not specified in group_vars
GROUP_VARS_FILE="$ANSIBLE_DIR/inventory/group_vars/all.yml"
if [ -f "$GROUP_VARS_FILE" ] && command -v yq &> /dev/null; then
  DEFAULT_DEPLOYMENT_MODE=$(yq eval '.deployment_mode // "docker"' "$GROUP_VARS_FILE")
else
  DEFAULT_DEPLOYMENT_MODE="docker"
fi

# Use default deployment mode (can be overridden by adding a 'deployment_mode' field per node in validator-config.yaml)
EXTRA_VARS="$EXTRA_VARS deployment_mode=$DEFAULT_DEPLOYMENT_MODE"

# Determine which playbook to run
if [ "$action" == "stop" ]; then
  PLAYBOOK="$ANSIBLE_DIR/playbooks/stop-nodes.yml"
  ACTION_MSG="stopping nodes"
else
  PLAYBOOK="$ANSIBLE_DIR/playbooks/site.yml"
  ACTION_MSG="deploying nodes"
fi

# Build ansible-playbook command
ANSIBLE_CMD="ansible-playbook"
ANSIBLE_CMD="$ANSIBLE_CMD -i $INVENTORY_FILE"
ANSIBLE_CMD="$ANSIBLE_CMD $PLAYBOOK"
ANSIBLE_CMD="$ANSIBLE_CMD -e \"$EXTRA_VARS\""

echo "Running Ansible playbook for $ACTION_MSG..."
echo "Command: $ANSIBLE_CMD"
echo ""

# Change to Ansible directory and execute
cd "$ANSIBLE_DIR"
eval $ANSIBLE_CMD

EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
  echo ""
  if [ "$action" == "stop" ]; then
    echo "✅ Ansible stop operation completed successfully!"
  else
    # Display summary of deployed nodes
    echo ""
    echo "=================================================="
    echo "Deployed Nodes Summary:"
    echo "=================================================="
    printf "%-15s | %-10s | %s\n" "Node" "Mode" "Docker Image"
    echo "--------------------------------------------------"

    # Get node names for summary
    if [[ "$node" == "all" ]]; then
      # Expand "all" to actual node names from config
      deployed_nodes=($(yq eval '.validators[].name' "$deploy_validator_config_file" 2>/dev/null))
    elif [[ "$node" == *","* ]]; then
      IFS=',' read -r -a deployed_nodes <<< "$node"
    else
      IFS=' ' read -r -a deployed_nodes <<< "$node"
    fi

    for node_name in "${deployed_nodes[@]}"; do
      # Get image from deploy-validator-config.yaml (overrides already merged)
      docker_image=$(yq eval ".validators[] | select(.name == \"$node_name\") | .image" "$deploy_validator_config_file" 2>/dev/null)
      printf "%-15s | %-10s | %s\n" "$node_name" "docker" "${docker_image:-unknown}"
    done
    echo "=================================================="
    echo ""
    echo "✅ Ansible deployment completed successfully!"
  fi
else
  echo ""
  if [ "$action" == "stop" ]; then
    echo "❌ Ansible stop operation failed with exit code $EXIT_CODE"
  else
    echo "❌ Ansible deployment failed with exit code $EXIT_CODE"
  fi
fi

exit $EXIT_CODE

