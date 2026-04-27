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
validator_config_file="$5"
sshKeyFile="$6"
useRoot="$7"  # Flag to use root user (defaults to current user)
action="$8"   # Action: "stop" to stop nodes, otherwise deploy
coreDumps="$9"  # Core dump configuration: "all", node names, or client types
skipGenesis="${10}"  # Set to "true" to skip genesis generation (e.g. when restarting with checkpoint sync)
checkpointSyncUrl="${11}"  # URL for checkpoint sync (when restarting with --restart-client)
dryRun="${12}"  # Set to "true" to run Ansible with --check --diff (no changes applied)
syncAllHosts="${13}"  # Set to "true" to sync config yamls to all hosts (used after --replace-with)
networkName="${14}"  # Network label applied to all metrics (e.g. devnet-3, testnet, mainnet)

# Determine SSH user: use root if --useRoot flag is set, otherwise use current user
if [ "$useRoot" == "true" ]; then
  sshUser="root"
else
  sshUser=$(whoami)  # Use current user
fi

# Validate required arguments
if [ -z "$configDir" ] || [ -z "$validator_config_file" ]; then
  echo "Error: Missing required arguments"
  echo "Usage: $0 <configDir> <node> <cleanData> <validatorConfig> <validator_config_file> [sshKeyFile] [useRoot] [action] [coreDumps]"
  exit 1
fi

echo "Deployment mode: ansible - routing to Ansible deployment"
echo "SSH user for remote connections: $sshUser"
# Note: Ansible prerequisites are validated in spin-node.sh before calling this script

# Generate ansible inventory from validator-config.yaml
ANSIBLE_DIR="$scriptDir/ansible"
INVENTORY_FILE="$ANSIBLE_DIR/inventory/hosts.yml"
PREPARE_INVENTORY="$ANSIBLE_DIR/inventory/hosts-prepare.yml"

# Regenerate if main inventory missing, prepare inventory missing, or validator config is newer
_regen_inv=false
if [ ! -f "$INVENTORY_FILE" ]; then
  _regen_inv=true
fi
if [ ! -f "$PREPARE_INVENTORY" ]; then
  _regen_inv=true
fi
if [ -f "$validator_config_file" ] && [ -f "$INVENTORY_FILE" ] && [ "$validator_config_file" -nt "$INVENTORY_FILE" ]; then
  _regen_inv=true
fi
if [ "$_regen_inv" = true ]; then
  echo "Generating Ansible inventory from validator-config.yaml..."
  "$scriptDir/generate-ansible-inventory.sh" "$validator_config_file" "$INVENTORY_FILE"
fi

# prepare.yml: one play per physical host (deduped by IP). Deploy still uses full hosts.yml.
EFFECTIVE_INVENTORY="$INVENTORY_FILE"
if [ "$action" == "prepare" ] && [ -f "$PREPARE_INVENTORY" ]; then
  EFFECTIVE_INVENTORY="$PREPARE_INVENTORY"
fi

# Update inventory file(s) with SSH key file and user if provided
if command -v yq &> /dev/null; then
  _inv_files=("$INVENTORY_FILE")
  [ -f "$PREPARE_INVENTORY" ] && _inv_files+=("$PREPARE_INVENTORY")
  for _inv in "${_inv_files[@]}"; do
    # Derive the group list dynamically from the inventory so newly added clients
    # (e.g. gean_nodes, lean_nodes) are automatically included without needing to
    # update this hardcoded list every time a new client type is added.
    all_groups=$(yq eval '.all.children | keys | .[]' "$_inv" 2>/dev/null || echo "")
    for group in $all_groups; do
      # Get all hosts in this group
      hosts=$(yq eval ".all.children.$group.hosts | keys | .[]" "$_inv" 2>/dev/null || echo "")
      for host in $hosts; do
        # Only update if it's a remote host (has ansible_host but not ansible_connection: local)
        connection=$(yq eval ".all.children.$group.hosts.$host.ansible_connection // \"\"" "$_inv" 2>/dev/null)
        if [ -z "$connection" ] || [ "$connection" != "local" ]; then
          # Set SSH user (defaults to current user, or root if --useRoot flag is set)
          yq eval -i ".all.children.$group.hosts.\"$host\".ansible_user = \"$sshUser\"" "$_inv"

          # Set SSH key file if provided
          if [ -n "$sshKeyFile" ]; then
            # Expand ~ to home directory if needed
            if [[ "$sshKeyFile" == ~* ]]; then
              sshKeyFile="${sshKeyFile/#\~/$HOME}"
            fi
            yq eval -i ".all.children.$group.hosts.\"$host\".ansible_ssh_private_key_file = \"$sshKeyFile\"" "$_inv"
            echo "Setting SSH private key file for $host: $sshKeyFile"
          fi
        fi
      done
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

# Pass the absolute path of the active validator config. ansible-playbook runs
# with cwd ansible/; lookup('file', ...) treats relative paths as relative to
# that directory, so a path like ansible-devnet/genesis/foo.yaml would break.
_local_vc_path="$validator_config_file"
if [[ "$_local_vc_path" != /* ]]; then
  _local_vc_path="$scriptDir/$_local_vc_path"
fi
EXTRA_VARS="$EXTRA_VARS local_validator_config_path=$_local_vc_path"

if [ -n "$coreDumps" ]; then
  EXTRA_VARS="$EXTRA_VARS enable_core_dumps=$coreDumps"
fi

if [ "$skipGenesis" == "true" ]; then
  EXTRA_VARS="$EXTRA_VARS skip_genesis=true"
fi

if [ -n "$checkpointSyncUrl" ]; then
  EXTRA_VARS="$EXTRA_VARS checkpoint_sync_url=$checkpointSyncUrl"
fi

if [ "$syncAllHosts" == "true" ]; then
  EXTRA_VARS="$EXTRA_VARS sync_all_hosts=true"
fi

EXTRA_VARS="$EXTRA_VARS network_name=$networkName"

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
elif [ "$action" == "prepare" ]; then
  PLAYBOOK="$ANSIBLE_DIR/playbooks/prepare.yml"
  ACTION_MSG="preparing servers"
else
  PLAYBOOK="$ANSIBLE_DIR/playbooks/site.yml"
  ACTION_MSG="deploying nodes"
fi

# Build ansible-playbook command
ANSIBLE_CMD="ansible-playbook"
ANSIBLE_CMD="$ANSIBLE_CMD -i $EFFECTIVE_INVENTORY"
ANSIBLE_CMD="$ANSIBLE_CMD $PLAYBOOK"
ANSIBLE_CMD="$ANSIBLE_CMD -e \"$EXTRA_VARS\""

# Dry-run: show what Ansible would change without applying anything.
if [ "$dryRun" == "true" ]; then
  ANSIBLE_CMD="$ANSIBLE_CMD --check --diff"
fi

echo "Running Ansible playbook for $ACTION_MSG..."
echo "Command: $ANSIBLE_CMD"
echo ""

# Change to Ansible directory and execute
cd "$ANSIBLE_DIR"
eval $ANSIBLE_CMD

EXIT_CODE=$?
_dry_tag=""
[ "$dryRun" == "true" ] && _dry_tag=" (dry-run — no changes applied)"
if [ $EXIT_CODE -eq 0 ]; then
  echo ""
  if [ "$action" == "stop" ]; then
    echo "✅ Ansible stop operation completed successfully!${_dry_tag}"
  elif [ "$action" == "prepare" ]; then
    echo "✅ Server preparation completed successfully!${_dry_tag}"
  else
    echo "✅ Ansible deployment completed successfully!${_dry_tag}"
  fi
else
  echo ""
  if [ "$action" == "stop" ]; then
    echo "❌ Ansible stop operation failed with exit code $EXIT_CODE"
  elif [ "$action" == "prepare" ]; then
    echo "❌ Server preparation failed with exit code $EXIT_CODE"
  else
    echo "❌ Ansible deployment failed with exit code $EXIT_CODE"
  fi
fi

exit $EXIT_CODE

