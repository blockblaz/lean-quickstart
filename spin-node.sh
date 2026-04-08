#!/bin/bash
# set -e

currentDir=$(pwd)
scriptDir=$(dirname $0)
if [ "$scriptDir" == "." ]; then
  scriptDir="$currentDir"
fi

# Save original args before parse-env.sh shifts them
_original_args="$*"

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

# Set up logging if --logs flag is enabled
if [ "$enableLogs" == "true" ]; then
    _log_dir="$scriptDir/tmp"
    mkdir -p "$_log_dir"
    _log_start=$(date -u +%s)
    _ts=$(date -u '+%d-%m-%Y-%H-%M')
    if [ "$deployment_mode" == "ansible" ]; then
        _log_prefix="ansible-run"
        _config_prefix="ansible"
    else
        _log_prefix="local-run"
        _config_prefix="local"
    fi
    _log_file="$_log_dir/${_log_prefix}-${_ts}.log"
    echo "$(date -u '+%Y-%m-%d %H:%M:%S') START spin-node.sh $_original_args" >> "$_log_dir/devnet.log"
    trap 'echo "$(date -u '\''+%Y-%m-%d %H:%M:%S'\'') END   spin-node.sh ($(( $(date -u +%s) - _log_start ))s) -> '"$_log_file"'" >> "'"$_log_dir"'/devnet.log"' EXIT
    exec > >(tee -a "$_log_file") 2>&1
    echo "Logging to $_log_file"
    # Copy validator config with timestamped name matching the run log
    if [ -n "$replaceWith" ]; then
        _config_copy="$_log_dir/${_config_prefix}-${networkName}-validator-config-replace-${_ts}.yaml"
    else
        _config_copy="$_log_dir/${_config_prefix}-${networkName}-validator-config-${_ts}.yaml"
    fi
    cp "$validator_config_file" "$_config_copy"
    echo "Validator config copied to $_config_copy"
fi

# If --subnets N is specified, expand the validator config template into a new
# file with N nodes per client (same IP, unique incremented ports and keys).
# This must run after configDir/validator_config_file are resolved so the
# generated file lands in the correct genesis directory.
if [ -n "$subnets" ] && [ "$subnets" -ge 1 ] 2>/dev/null; then
  if ! [[ "$subnets" =~ ^[0-9]+$ ]] || [ "$subnets" -lt 1 ] || [ "$subnets" -gt 5 ]; then
    echo "Error: --subnets requires an integer between 1 and 5, got: $subnets"
    exit 1
  fi

  if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is required to generate the subnet config."
    exit 1
  fi

  expanded_config="${configDir}/validator-config-subnets-${subnets}.yaml"
  [ "$dryRun" == "true" ] && echo "[DRY RUN] Generating subnet config preview (no deployment will occur)"
  echo "Generating subnet config ($subnets subnet(s) per client) → $expanded_config"

  if ! python3 "$scriptDir/generate-subnet-config.py" \
      "$validator_config_file" "$subnets" "$expanded_config"; then
    echo "❌ Failed to generate subnet config."
    exit 1
  fi

  validator_config_file="$expanded_config"
  echo "Using expanded config: $validator_config_file"
fi

# Handle --prepare mode: verify and install required software on all remote servers.
# Must run after deployment_mode is resolved but before genesis setup.
if [ -n "$prepareMode" ] && [ "$prepareMode" == "true" ]; then
  if [ "$deployment_mode" != "ansible" ]; then
    echo "Error: --prepare can only be used in ansible mode."
    echo "Set deployment_mode: ansible in your validator-config.yaml or pass --deploymentMode ansible"
    exit 1
  fi

  # Reject flags that have no meaning in prepare mode.
  ignored_flags=()
  [ -n "$node" ]                && ignored_flags+=("--node")
  [ -n "$cleanData" ]           && ignored_flags+=("--cleanData")
  [ -n "$generateGenesis" ]     && ignored_flags+=("--generateGenesis")
  [ -n "$FORCE_KEYGEN_FLAG" ]   && ignored_flags+=("--forceKeyGen")
  [ -n "$stopNodes" ]           && ignored_flags+=("--stop")
  [ -n "$restartClient" ]       && ignored_flags+=("--restart-client")
  [ -n "$checkpointSyncUrl" ]   && ignored_flags+=("--checkpoint-sync-url")
  [ -n "$dockerTag" ]           && ignored_flags+=("--tag")
  [ -n "$aggregatorNode" ]      && ignored_flags+=("--aggregator")
  [ -n "$coreDumps" ]           && ignored_flags+=("--coreDumps")
  [ -n "$enableMetrics" ]       && ignored_flags+=("--metrics")
  [ -n "$popupTerminal" ]       && ignored_flags+=("--popupTerminal")
  [ -n "$dockerWithSudo" ]      && ignored_flags+=("--dockerWithSudo")
  [ -n "$skipLeanpoint" ]       && ignored_flags+=("--skip-leanpoint")
  [ -n "$skipNemo" ]            && ignored_flags+=("--skip-nemo")
  [ -n "$validatorConfig" ] && [ "$validatorConfig" != "genesis_bootnode" ] \
                                && ignored_flags+=("--validatorConfig")

  if [ ${#ignored_flags[@]} -gt 0 ]; then
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                        ❌  ERROR                            ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║  --prepare does not accept the following flag(s):           ║"
    for flag in "${ignored_flags[@]}"; do
      printf  "║    %-60s║\n" "• $flag"
    done
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║  Allowed flags with --prepare:                              ║"
    echo "║    • --sshKey / --private-key                               ║"
    echo "║    • --useRoot                                              ║"
    echo "║    • --deploymentMode ansible                               ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    exit 1
  fi

  if ! command -v ansible-playbook &> /dev/null; then
    echo "Error: ansible-playbook is not installed."
    echo "Install Ansible: brew install ansible (macOS) or pip install ansible"
    exit 1
  fi

  if [ "$dryRun" == "true" ]; then
    echo "[DRY RUN] Would prepare remote servers — running Ansible with --check --diff"
  else
    echo "Preparing remote servers (verifying and installing required software)..."
  fi

  if ! "$scriptDir/run-ansible.sh" "$configDir" "" "" "" "$validator_config_file" "$sshKeyFile" "$useRoot" "prepare" "" "" "" "$dryRun" "" "$networkName"; then
    echo "❌ Server preparation failed."
    exit 1
  fi

  [ "$dryRun" == "true" ] && echo "✅ Dry-run complete — no changes were made." || echo "✅ All remote servers are prepared."
  exit 0
fi

#1. setup genesis params and run genesis generator
if [ "$dryRun" == "true" ]; then
  echo "[DRY RUN] Skipping genesis generation (set-up.sh would run here)"
  node_setup="${node_setup:-docker}"  # ensure local-loop variable has a default
else
  source "$(dirname $0)/set-up.sh"
  # ✅ Genesis generator implemented using PK's eth-beacon-genesis tool
  # Generates: validators.yaml, nodes.yaml, genesis.json, genesis.ssz, and .key files
fi

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

# Aggregator selection — one aggregator per subnet.
#
# Skipped entirely for --restart-client: restarting a single node must not
# disturb the existing isAggregator assignments for the rest of the network.
#
# Subnet membership is read from the explicit 'subnet:' field in the config,
# which generate-subnet-config.py writes when --subnets N is used.
# Nodes without a 'subnet' field (standard single-subnet configs) all
# default to subnet 0 regardless of their name suffix.
#
# When --aggregator is specified, that node is used as the aggregator for
# its own subnet; all other subnets still get a random selection (still
# excluding that node's client type from pools on other subnets).
#
# Default random mode (no --aggregator): aggregators are unique by CLIENT
# (prefix before the first '_', e.g. zeam from zeam_0). Example with 5 subnets:
# if zeam_* is chosen for subnet 0, no zeam_* node may be aggregator on
# subnets 1–4. If subnets outnumber distinct clients, the pool is exhausted
# and we fall back to unrestricted random with a warning.

# Helper: get the subnet index for a node from the config (defaults to 0).
_node_subnet() {
  yq eval ".validators[] | select(.name == \"$1\") | .subnet // 0" "$validator_config_file"
}

# Helper: client type prefix (matches generate-subnet-config.py _client_name).
_client_prefix() {
  case "$1" in
    *_*) printf '%s\n' "${1%%_*}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

if [ -n "$restartClient" ]; then
  echo "Note: skipping aggregator selection — --restart-client retains existing isAggregator assignments."
  _aggregator_summary=()
else

  # If --aggregator was given, validate it exists before doing anything else.
  if [ -n "$aggregatorNode" ]; then
    aggregator_found=false
    for available_node in "${nodes[@]}"; do
      if [[ "$aggregatorNode" == "$available_node" ]]; then
        aggregator_found=true
        break
      fi
    done
    if [[ "$aggregator_found" == false ]]; then
      echo "Error: Specified aggregator '$aggregatorNode' not found in validator config"
      echo "Available nodes: ${nodes[@]}"
      exit 1
    fi
  fi

  # Collect unique subnet indices from the 'subnet' field (0 when absent).
  _subnet_indices=()
  for _node in "${nodes[@]}"; do
    _subnet_indices+=("$(_node_subnet "$_node")")
  done
  _unique_subnets=($(printf '%s\n' "${_subnet_indices[@]}" | sort -un))

  echo "Detected ${#_unique_subnets[@]} subnet(s): ${_unique_subnets[*]}"

  # Snapshot which nodes already have isAggregator: true before we reset anything.
  # This lets us honour manual edits in the YAML when no --aggregator flag was passed.
  # Uses dynamic variable names (_preset_agg_<subnet>) for bash 3.2 compatibility
  # (bash 3.2 ships with macOS and does not support declare -A).
  for _node in "${nodes[@]}"; do
    _is_agg=$(yq eval ".validators[] | select(.name == \"$_node\") | .isAggregator" "$validator_config_file")
    if [[ "$_is_agg" == "true" ]]; then
      _sn="$(_node_subnet "$_node")"
      _varname="_preset_agg_${_sn}"
      # Keep the first preset aggregator found per subnet.
      [[ -z "${!_varname:-}" ]] && printf -v "$_varname" '%s' "$_node"
    fi
  done

  # Reset every node's isAggregator flag (skipped in dry-run).
  if [ "$dryRun" != "true" ]; then
    yq eval -i '.validators[].isAggregator = false' "$validator_config_file"
  fi

  # Select one aggregator per subnet and set the flag.
  # Priority: 1) --aggregator CLI flag  2) pre-existing isAggregator: true  3) random
  # _used_agg_prefixes: client types already chosen (default random / preset / --aggregator).
  _aggregator_summary=()
  _used_agg_prefixes=" "
  for _subnet_idx in "${_unique_subnets[@]}"; do
    _subnet_nodes=()
    for _node in "${nodes[@]}"; do
      [[ "$(_node_subnet "$_node")" == "$_subnet_idx" ]] && _subnet_nodes+=("$_node")
    done

    _selected_agg=""

    if [ -n "$aggregatorNode" ] && [[ "$(_node_subnet "$aggregatorNode")" == "$_subnet_idx" ]]; then
      # 1. Explicit --aggregator flag.
      _selected_agg="$aggregatorNode"
    elif _pv="_preset_agg_${_subnet_idx}"; [ -n "${!_pv:-}" ]; then
      # 2. A node had isAggregator: true in the config — respect the manual choice.
      _preset="${!_pv}"
      # Validate the preset node is still in the active nodes list.
      _preset_valid=false
      for _n in "${_subnet_nodes[@]}"; do
        [[ "$_n" == "$_preset" ]] && _preset_valid=true && break
      done
      if [[ "$_preset_valid" == "true" ]]; then
        _selected_agg="$_preset"
        # Default mode: one client type at most once across subnets — drop conflicting presets.
        if [ -z "$aggregatorNode" ]; then
          _pp="$(_client_prefix "$_selected_agg")"
          if [[ "$_used_agg_prefixes" == *" $_pp "* ]]; then
            echo "Warning: preset aggregator '$_preset' (client $_pp) already aggregates another subnet; selecting randomly in subnet $_subnet_idx." >&2
            _selected_agg=""
          fi
        fi
      else
        # Preset node no longer exists — fall back to random and warn.
        echo "Warning: preset aggregator '$_preset' for subnet $_subnet_idx is not in the active node list; selecting randomly." >&2
        _selected_agg=""
      fi
    fi

    # 3. Random (or preset fallback): prefer client types not yet used as aggregator.
    if [ -z "$_selected_agg" ]; then
      _eligible_aggs=()
      for _n in "${_subnet_nodes[@]}"; do
        _np="$(_client_prefix "$_n")"
        case "$_used_agg_prefixes" in
          *" $_np "*) : ;;
          *) _eligible_aggs+=("$_n") ;;
        esac
      done
      if [ ${#_eligible_aggs[@]} -eq 0 ] && [ ${#_subnet_nodes[@]} -gt 0 ]; then
        echo "Warning: subnet $_subnet_idx — no unused client type left for aggregator (subnets > distinct clients?); picking among all nodes in this subnet." >&2
        _eligible_aggs=("${_subnet_nodes[@]}")
      fi
      if [ ${#_eligible_aggs[@]} -gt 0 ]; then
        _selected_agg="${_eligible_aggs[$((RANDOM % ${#_eligible_aggs[@]}))]}"
      else
        echo "Error: subnet $_subnet_idx has no nodes to select an aggregator from." >&2
        exit 1
      fi
    fi

    _sel_pref="$(_client_prefix "$_selected_agg")"
    _used_agg_prefixes+="$_sel_pref "

    if [ "$dryRun" != "true" ]; then
      yq eval -i "(.validators[] | select(.name == \"$_selected_agg\") | .isAggregator) = true" "$validator_config_file"
    fi
    _aggregator_summary+=("subnet $_subnet_idx → $_selected_agg")
  done

  # Verify the invariant: exactly 1 aggregator per subnet (skipped in dry-run).
  if [ "$dryRun" != "true" ]; then
    _verify_failed=false
    for _subnet_idx in "${_unique_subnets[@]}"; do
      _agg_count=0
      for _node in "${nodes[@]}"; do
        if [[ "$(_node_subnet "$_node")" == "$_subnet_idx" ]]; then
          _is_agg=$(yq eval ".validators[] | select(.name == \"$_node\") | .isAggregator" "$validator_config_file")
          [[ "$_is_agg" == "true" ]] && _agg_count=$((_agg_count + 1))
        fi
      done
      if [ "$_agg_count" -ne 1 ]; then
        echo "Error: subnet $_subnet_idx has $_agg_count aggregator(s) — expected exactly 1" >&2
        _verify_failed=true
      fi
    done
    if [ "$_verify_failed" == "true" ]; then
      echo "Aggregator invariant check failed. Aborting." >&2
      exit 1
    fi
  fi

fi  # end: aggregator selection (skipped for --restart-client)

# Print a prominent aggregator summary banner (only when aggregator selection ran).
if [ ${#_aggregator_summary[@]} -gt 0 ]; then
  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║               🗳  Aggregator Selection                      ║"
  echo "╠══════════════════════════════════════════════════════════════╣"
  for _line in "${_aggregator_summary[@]}"; do
    printf "║  %-60s║\n" "$_line"
  done
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""
fi

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

  # --- Handle --replace-with: swap client implementations ---
  # Uses parallel arrays (bash 3.x compatible, no associative arrays)
  if [[ -n "$replaceWith" ]]; then
    IFS=',' read -r -a replace_nodes <<< "$replaceWith"

    # Build replacement pairs as parallel arrays
    replace_old_names=()
    replace_new_names=()
    has_replacements=false
    i=0
    for old_name in "${requested_nodes[@]}"; do
      new_name=""
      if [ $i -lt ${#replace_nodes[@]} ]; then
        new_name=$(echo "${replace_nodes[$i]}" | xargs)  # trim whitespace
      fi
      if [ -n "$new_name" ] && [ "$new_name" != "$old_name" ]; then
        replace_old_names+=("$old_name")
        replace_new_names+=("$new_name")
        has_replacements=true
        echo "Will replace: $old_name → $new_name"
      fi
      i=$((i + 1))
    done

    # Warn about extra --replace-with entries beyond --restart-client count
    if [ ${#replace_nodes[@]} -gt ${#requested_nodes[@]} ]; then
      echo "Warning: --replace-with has more entries (${#replace_nodes[@]}) than --restart-client (${#requested_nodes[@]}). Extra entries ignored."
    fi

    if [ "$has_replacements" = true ]; then
      # 1. Stop old containers and clean data BEFORE config changes (inventory still resolves to old names)
      echo "Stopping old containers and cleaning data before replacement..."
      for idx in "${!replace_old_names[@]}"; do
        old_name="${replace_old_names[$idx]}"
        if [ "$deployment_mode" == "ansible" ]; then
          echo "Stopping $old_name and cleaning remote data via Ansible..."
          "$scriptDir/run-ansible.sh" "$configDir" "$old_name" "true" "$validatorConfig" "$validator_config_file" "$sshKeyFile" "$useRoot" "stop" "" "true" "" "" "" "$networkName" || {
            echo "Warning: Failed to stop $old_name via Ansible, continuing..."
          }
        else
          echo "Stopping local container $old_name..."
          if [ -n "$dockerWithSudo" ]; then
            sudo docker rm -f "$old_name" 2>/dev/null || true
          else
            docker rm -f "$old_name" 2>/dev/null || true
          fi
          # Remove old local data directory (different clients have different data structures)
          old_data_dir="$dataDir/$old_name"
          if [ -d "$old_data_dir" ]; then
            rm -rf "$old_data_dir"
            echo "  Removed data dir $old_name"
          fi
        fi
      done

      # 2. Update config files (rename old → new)
      for idx in "${!replace_old_names[@]}"; do
        old_name="${replace_old_names[$idx]}"
        new_name="${replace_new_names[$idx]}"
        echo "Updating config files: $old_name → $new_name"

        # validator-config.yaml: rename .validators[].name
        yq eval -i "(.validators[] | select(.name == \"$old_name\") | .name) = \"$new_name\"" "$validator_config_file"

        # validators.yaml: rename top-level key (two steps: copy then delete, single expression doesn't work)
        validators_file="$configDir/validators.yaml"
        if [ -f "$validators_file" ]; then
          yq eval -i ".$new_name = .$old_name" "$validators_file"
          yq eval -i "del(.$old_name)" "$validators_file"
        fi

        # annotated_validators.yaml: rename top-level key
        annotated_file="$configDir/annotated_validators.yaml"
        if [ -f "$annotated_file" ]; then
          yq eval -i ".$new_name = .$old_name" "$annotated_file"
          yq eval -i "del(.$old_name)" "$annotated_file"
        fi

        # Rename key file (overwrite if destination exists from a previous run)
        if [ -f "$configDir/$old_name.key" ]; then
          mv -f "$configDir/$old_name.key" "$configDir/$new_name.key"
          echo "  Renamed $old_name.key → $new_name.key"
        fi
      done

      # 3. Update spin_nodes array with new names
      for i in "${!spin_nodes[@]}"; do
        old="${spin_nodes[$i]}"
        for idx in "${!replace_old_names[@]}"; do
          if [ "$old" = "${replace_old_names[$idx]}" ]; then
            spin_nodes[$i]="${replace_new_names[$idx]}"
            break
          fi
        done
      done

      # Re-read nodes from updated config (needed for aggregator and downstream logic)
      nodes=($(yq eval '.validators[].name' "$validator_config_file"))

      # Ensure inventory is regenerated on next run-ansible.sh call
      # (the stop call may have regenerated it with old names)
      touch "$validator_config_file"

      echo "Updated spin_nodes: ${spin_nodes[*]}"
      echo "Config files updated successfully."
    fi
  fi

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
  # deploy-nodes.yml syncs config files to the target host, so copy-genesis to all hosts is not needed
  ansible_skip_genesis="false"
  [[ "$restart_with_checkpoint_sync" == "true" ]] && ansible_skip_genesis="true"

  # Determine checkpoint_sync_url for Ansible (when restarting with checkpoint sync)
  ansible_checkpoint_url=""
  [[ "$restart_with_checkpoint_sync" == "true" ]] && [[ -n "$checkpointSyncUrl" ]] && ansible_checkpoint_url="$checkpointSyncUrl"

  # Handle stop action
  if [ -n "$stopNodes" ] && [ "$stopNodes" == "true" ]; then
    echo "Stopping nodes via Ansible..."
    if ! "$scriptDir/run-ansible.sh" "$configDir" "$ansible_node_arg" "$cleanData" "$validatorConfig" "$validator_config_file" "$sshKeyFile" "$useRoot" "stop" "$coreDumps" "$ansible_skip_genesis" "" "$dryRun" "" "$networkName"; then
      echo "❌ Ansible stop operation failed. Exiting."
      exit 1
    fi
    exit 0
  fi
  
  # When --replace-with already cleaned data in the stop step, don't pass clean_data to deploy
  # (the old node name no longer exists in config, so clean-node-data.yml would fail resolving it)
  ansible_clean_data="$cleanData"
  [[ "${has_replacements:-false}" = "true" ]] && ansible_clean_data=""

  # Call separate Ansible execution script
  # If Ansible deployment fails, exit immediately (don't fall through to local deployment)
  if [ "$dryRun" == "true" ]; then
    echo "[DRY RUN] Would deploy via Ansible — running playbook with --check --diff"
  fi
  ansible_sync_all_hosts=""
  [[ "${has_replacements:-false}" = "true" ]] && ansible_sync_all_hosts="true"

  if ! "$scriptDir/run-ansible.sh" "$configDir" "$ansible_node_arg" "$ansible_clean_data" "$validatorConfig" "$validator_config_file" "$sshKeyFile" "$useRoot" "" "$coreDumps" "$ansible_skip_genesis" "$ansible_checkpoint_url" "$dryRun" "$ansible_sync_all_hosts" "$networkName"; then
    echo "❌ Ansible deployment failed. Exiting."
    exit 1
  fi

  if [ -z "$skipLeanpoint" ] && { [ "$restart_with_checkpoint_sync" != "true" ] || [ "${has_replacements:-false}" = "true" ]; }; then
    # Sync leanpoint upstreams to tooling server and restart remote container (no 5th arg = remote)
    if ! "$scriptDir/sync-leanpoint-upstreams.sh" "$validator_config_file" "$scriptDir" "$sshKeyFile" "$useRoot"; then
      echo "Warning: leanpoint sync failed. If the tooling server requires a specific SSH key, run with: --sshKey <path-to-key>"
    fi
  fi

  if [ -z "$skipNemo" ]; then
    _nemo_reset_db=0
    [ -n "$generateGenesis" ] && _nemo_reset_db=1
    if ! NEMO_RESET_DB="$_nemo_reset_db" "$scriptDir/sync-nemo-tooling.sh" "$validator_config_file" "$scriptDir" "$sshKeyFile" "$useRoot"; then
      echo "Warning: Nemo tooling sync failed. Pass --sshKey <path-to-key> if the tooling server requires it, or use --skip-nemo to skip."
    fi
  fi

  # Push genesis time metric to Pushgateway if available
  _pushgateway_url="${PUSHGATEWAY_URL:-http://46.225.10.32:9091}"
  _genesis_config="$configDir/config.yaml"
  if [ -f "$_genesis_config" ]; then
    _genesis_time=$(grep "GENESIS_TIME:" "$_genesis_config" | awk '{print $2}')
    if [ -n "$_genesis_time" ]; then
      echo "lean_genesis_time $_genesis_time" | curl -s --data-binary @- \
        "$_pushgateway_url/metrics/job/lean-quickstart/network/$networkName" || \
        echo "Warning: Failed to push lean_genesis_time to Pushgateway."
    fi
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

  # Stop local leanpoint container if running
  if [ -n "$dockerWithSudo" ]; then
    sudo docker rm -f leanpoint 2>/dev/null || echo "  Container leanpoint not found or already stopped"
    sudo docker rm -f nemo 2>/dev/null || echo "  Container nemo not found or already stopped"
  else
    docker rm -f leanpoint 2>/dev/null || echo "  Container leanpoint not found or already stopped"
    docker rm -f nemo 2>/dev/null || echo "  Container nemo not found or already stopped"
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
  # extract client config FIRST before printing
  IFS='_' read -r -a elements <<< "$item"
  client="${elements[0]}"

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

  if [ "$dryRun" == "true" ]; then
    echo "[DRY RUN] Would execute: $execCmd"
    pid=0
  else
    echo "$execCmd"
    eval "$execCmd" &
    pid=$!
  fi
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

# Deploy leanpoint: locally (local devnet) or sync to tooling server (Ansible), unless --skip-leanpoint
# Skip leanpoint during checkpoint sync restart (node list hasn't changed)
local_leanpoint_deployed=0
if [ -z "$skipLeanpoint" ] && { [ "$restart_with_checkpoint_sync" != "true" ] || [ "${has_replacements:-false}" = "true" ]; }; then
  if "$scriptDir/sync-leanpoint-upstreams.sh" "$validator_config_file" "$scriptDir" "$sshKeyFile" "$useRoot" "$dataDir"; then
    local_leanpoint_deployed=1
  else
    echo "Warning: leanpoint deploy failed. For remote sync, pass --sshKey <path-to-key> if the tooling server requires it."
  fi
fi

# Nemo explorer: same tooling server (Ansible) or local Docker; DB reset only with --generateGenesis
local_nemo_deployed=0
if [ -z "$skipNemo" ]; then
  _nemo_reset_db=0
  [ -n "$generateGenesis" ] && _nemo_reset_db=1
  if NEMO_RESET_DB="$_nemo_reset_db" "$scriptDir/sync-nemo-tooling.sh" "$validator_config_file" "$scriptDir" "$sshKeyFile" "$useRoot" "$dataDir"; then
    local_nemo_deployed=1
  else
    echo "Warning: Nemo deploy failed. Pass --sshKey if needed, or --skip-nemo to skip."
  fi
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

  if [ "${local_leanpoint_deployed:-0}" = "1" ]; then
    execCmd="docker rm -f leanpoint"
    [ -n "$dockerWithSudo" ] && execCmd="sudo $execCmd"
    eval "$execCmd" 2>/dev/null || true
  fi

  if [ "${local_nemo_deployed:-0}" = "1" ]; then
    execCmd="docker rm -f nemo"
    [ -n "$dockerWithSudo" ] && execCmd="sudo $execCmd"
    eval "$execCmd" 2>/dev/null || true
  fi

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
