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
generateGenesis="$3"
cleanData="$4"
validatorConfig="$5"
validator_config_file="$6"

# Validate required arguments
if [ -z "$configDir" ] || [ -z "$validator_config_file" ]; then
  echo "Error: Missing required arguments"
  echo "Usage: $0 <configDir> <node> <generateGenesis> <cleanData> <validatorConfig> <validator_config_file>"
  exit 1
fi

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
fi

exit $EXIT_CODE

