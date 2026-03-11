#!/bin/bash
# sync-leanpoint-upstreams.sh: Regenerate upstreams.json from validator-config.yaml,
# rsync it to the tooling server, and restart the leanpoint container.
#
# Used after validator nodes are spun up so leanpoint monitors the current set
# of nodes. Called at the end of spin-node.sh (both Ansible and local deployment).
#
# Usage:
#   sync-leanpoint-upstreams.sh <validator_config_file> <script_dir> [ssh_key_file] [use_root]
#
# Env (optional):
#   TOOLING_SERVER          Tooling server host (default: 46.225.10.32)
#   TOOLING_SERVER_USER     SSH user on tooling server (default: root)
#   LEANPOINT_DIR           Path containing convert-validator-config.py (default: script_dir)
#   REMOTE_UPSTREAMS_PATH   Remote path for upstreams.json (default: /etc/leanpoint/upstreams.json)
#   LEANPOINT_CONTAINER     Docker container name on tooling server (default: leanpoint)
#   LEANPOINT_IMAGE         Docker image to pull and run (default: 0xpartha/leanpoint:latest)
#   LEANPOINT_SYNC_DISABLED Set to 1 to skip sync (e.g. when tooling server is not used)

set -e

validator_config_file="${1:?Usage: sync-leanpoint-upstreams.sh <validator_config_file> <script_dir> [ssh_key_file] [use_root]}"
scriptDir="${2:?Usage: sync-leanpoint-upstreams.sh <validator_config_file> <script_dir> [ssh_key_file] [use_root]}"
sshKeyFile="${3:-}"
useRoot="${4:-false}"

TOOLING_SERVER="${TOOLING_SERVER:-46.225.10.32}"
TOOLING_SERVER_USER="${TOOLING_SERVER_USER:-root}"
LEANPOINT_DIR="${LEANPOINT_DIR:-$scriptDir}"
REMOTE_UPSTREAMS_PATH="${REMOTE_UPSTREAMS_PATH:-/etc/leanpoint/upstreams.json}"
LEANPOINT_CONTAINER="${LEANPOINT_CONTAINER:-leanpoint}"
LEANPOINT_IMAGE="${LEANPOINT_IMAGE:-0xpartha/leanpoint:latest}"

if [ "${LEANPOINT_SYNC_DISABLED:-0}" = "1" ]; then
  echo "Leanpoint sync disabled (LEANPOINT_SYNC_DISABLED=1), skipping."
  exit 0
fi

convert_script="$LEANPOINT_DIR/convert-validator-config.py"
if [ ! -f "$convert_script" ]; then
  echo "Warning: convert-validator-config.py not found at $convert_script, skipping leanpoint sync."
  exit 0
fi

if [ ! -f "$validator_config_file" ]; then
  echo "Warning: validator config not found at $validator_config_file, skipping leanpoint sync."
  exit 0
fi

# Build SSH/rsync target and optional key args
remote_target="${TOOLING_SERVER_USER}@${TOOLING_SERVER}"
ssh_cmd="ssh -o StrictHostKeyChecking=no"
if [ -n "$sshKeyFile" ]; then
  key_path="$sshKeyFile"
  [[ "$key_path" == ~* ]] && key_path="${key_path/#\~/$HOME}"
  if [ -f "$key_path" ]; then
    ssh_cmd="ssh -i $key_path -o StrictHostKeyChecking=no"
  fi
fi

# Generate upstreams.json (no --docker: use real validator IPs for remote leanpoint)
out_file=$(mktemp)
trap "rm -f $out_file" EXIT
python3 "$convert_script" "$validator_config_file" "$out_file" || {
  echo "Warning: convert-validator-config.py failed, skipping leanpoint sync."
  exit 0
}

# Ensure remote directory exists, then rsync
remote_dir=$(dirname "$REMOTE_UPSTREAMS_PATH")
$ssh_cmd "$remote_target" "mkdir -p $remote_dir"
rsync -e "$ssh_cmd" "$out_file" "${remote_target}:${REMOTE_UPSTREAMS_PATH}"

# Pull latest image, recreate container so it runs the new image
$ssh_cmd "$remote_target" "docker pull $LEANPOINT_IMAGE && docker stop $LEANPOINT_CONTAINER 2>/dev/null || true; docker rm $LEANPOINT_CONTAINER 2>/dev/null || true; docker run -d --name $LEANPOINT_CONTAINER --restart unless-stopped -p 5555:5555 -v $REMOTE_UPSTREAMS_PATH:/etc/leanpoint/upstreams.json:ro $LEANPOINT_IMAGE"

echo "Leanpoint upstreams synced to $TOOLING_SERVER, image $LEANPOINT_IMAGE pulled, container '$LEANPOINT_CONTAINER' recreated."
