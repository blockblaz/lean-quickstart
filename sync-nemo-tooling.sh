#!/bin/bash
# sync-nemo-tooling.sh — Build LEAN_API_URL from validator-config.yaml (all validators +
# their apiPort/httpPort), deploy Nemo on the tooling server or locally.
#
# On every deploy: SQLite data dir is wiped so Nemo starts with a fresh DB.
# Image: docker pull NEMO_IMAGE, then docker run --pull=always so :latest is refreshed from the registry.
#
# Usage:
#   sync-nemo-tooling.sh <validator_config_file> <script_dir> [ssh_key_file] [use_root] [local_data_dir]
#
# - If local_data_dir (5th arg) is set: run Nemo in Docker locally with host.docker.internal
#   (--docker URL generation). Data: <local_data_dir>/nemo-data (cleared each run).
# - Otherwise: rsync env file to tooling server, clear remote data dir, recreate container.
#
# Env (optional):
#   TOOLING_SERVER          (default: 46.225.10.32)
#   TOOLING_SERVER_USER     (default: root)
#   LEANPOINT_DIR           Path with convert-validator-config.py (default: script_dir)
#   REMOTE_NEMO_ENV_PATH    Remote env file (default: /etc/nemo/nemo.env)
#   REMOTE_NEMO_DATA_DIR    Remote SQLite host dir (default: /opt/nemo/data)
#   NEMO_CONTAINER          (default: nemo)
#   NEMO_IMAGE              (default: 0xpartha/nemo:latest)
#   NEMO_SYNC_DISABLED      Set to 1 to skip
#   NEMO_HOST_PORT          Host port published for Nemo HTTP (default: 5053).
#                           Must differ from LEANPOINT_HOST_PORT (default 5555) on the same host.
#   LEANPOINT_HOST_PORT     Only used for clash check (default 5555); set if you override leanpoint's host port.
#   NEMO_DOCKER_PLATFORM    Optional. linux/arm64 or linux/amd64 for pull/run. If unset, derived from
#                           `uname -m` on the machine that runs Docker (local host or tooling server).
#                           --platform is only passed when the registry manifest lists that architecture
#                           (multi-arch index). Single-arch images omit it so pull/run still work; publish
#                           a multi-arch image (see nemo/docker-bake.hcl) to get native pulls without emulation.

set -e

# Map kernel machine name to Docker platform (multi-arch images, e.g. 0xpartha/nemo:latest).
nemo_docker_platform_from_uname() {
  case "${1:-}" in
    aarch64 | arm64) echo linux/arm64 ;;
    x86_64 | amd64) echo linux/amd64 ;;
    *) echo "" ;;
  esac
}

# True if manifest inspect shows a multi-arch index that includes this CPU architecture.
# Single-platform images (no "manifests" array) return false so we do not pass --platform
# (avoids "no matching manifest" when the tag is amd64-only).
nemo_image_manifest_includes_arch() {
  local image="$1" plat="$2"
  local arch="${plat#linux/}"
  case "$arch" in aarch64) arch=arm64 ;; esac
  local json
  json=$(docker manifest inspect "$image" 2>/dev/null) || return 1
  echo "$json" | grep -q '"manifests"' || return 1
  echo "$json" | grep -qE "\"architecture\"[[:space:]]*:[[:space:]]*\"$arch\""
}

# Optional pull/run --platform only when the registry has a matching manifest (and platform is known).
nemo_docker_platform_args_for_machine() {
  local machine="$1"
  local plat="${NEMO_DOCKER_PLATFORM:-}"
  if [ -z "$plat" ]; then
    plat=$(nemo_docker_platform_from_uname "$machine") || true
  fi
  if [ -z "$plat" ]; then
    return 0
  fi
  if nemo_image_manifest_includes_arch "$NEMO_IMAGE" "$plat"; then
    printf '%s' "--platform $plat"
  fi
}

validator_config_file="${1:?Usage: sync-nemo-tooling.sh <validator_config_file> <script_dir> [ssh_key_file] [use_root] [local_data_dir]}"
scriptDir="${2:?Usage: sync-nemo-tooling.sh <validator_config_file> <script_dir> [ssh_key_file] [use_root] [local_data_dir]}"
sshKeyFile="${3:-}"
useRoot="${4:-false}"
local_data_dir="${5:-}"

TOOLING_SERVER="${TOOLING_SERVER:-46.225.10.32}"
TOOLING_SERVER_USER="${TOOLING_SERVER_USER:-root}"
LEANPOINT_DIR="${LEANPOINT_DIR:-$scriptDir}"
REMOTE_NEMO_ENV_PATH="${REMOTE_NEMO_ENV_PATH:-/etc/nemo/nemo.env}"
REMOTE_NEMO_DATA_DIR="${REMOTE_NEMO_DATA_DIR:-/opt/nemo/data}"
NEMO_CONTAINER="${NEMO_CONTAINER:-nemo}"
NEMO_IMAGE="${NEMO_IMAGE:-0xpartha/nemo:latest}"
NEMO_HOST_PORT="${NEMO_HOST_PORT:-5053}"
LEANPOINT_HOST_PORT="${LEANPOINT_HOST_PORT:-5555}"

if [ "${NEMO_HOST_PORT}" = "${LEANPOINT_HOST_PORT}" ]; then
  echo "Error: NEMO_HOST_PORT (${NEMO_HOST_PORT}) must not equal LEANPOINT_HOST_PORT (leanpoint also binds that port on the tooling host)." >&2
  exit 1
fi

if [ "${NEMO_SYNC_DISABLED:-0}" = "1" ]; then
  echo "Nemo sync disabled (NEMO_SYNC_DISABLED=1), skipping."
  exit 0
fi

convert_script="$LEANPOINT_DIR/convert-validator-config.py"
if [ ! -f "$convert_script" ]; then
  echo "Warning: convert-validator-config.py not found at $convert_script, skipping Nemo sync."
  exit 0
fi

if [ ! -f "$validator_config_file" ]; then
  echo "Warning: validator config not found at $validator_config_file, skipping Nemo sync."
  exit 0
fi

run_local_nemo_container() {
  local env_file="$1"
  local data_vol="$2"
  local plat_args
  plat_args=$(nemo_docker_platform_args_for_machine "$(uname -m)")
  # Always fetch the current registry manifest for this tag (e.g. :latest), then run with --pull=always as a second guard.
  # --platform is used only when the image is a multi-arch index that lists this host's arch (native pull, no mismatch warning).
  # shellcheck disable=SC2086
  docker pull $plat_args "$NEMO_IMAGE"
  docker stop "$NEMO_CONTAINER" 2>/dev/null || true
  docker rm -f "$NEMO_CONTAINER" 2>/dev/null || true
  # shellcheck disable=SC2086
  docker run -d --pull=always $plat_args --name "$NEMO_CONTAINER" --restart unless-stopped \
    -p "${NEMO_HOST_PORT}:5053" \
    --env-file "$env_file" \
    -v "$data_vol:/data" \
    --add-host=host.docker.internal:host-gateway \
    "$NEMO_IMAGE"
}

# --- Local: Docker on this machine, validators on host ---
if [ -n "$local_data_dir" ]; then
  mkdir -p "$local_data_dir"
  nemo_data="$local_data_dir/nemo-data"
  mkdir -p "$nemo_data"
  rm -rf "${nemo_data:?}/"*
  env_local="$local_data_dir/nemo.env"
  python3 "$convert_script" --write-nemo-env "$env_local" "$validator_config_file" --docker || {
    echo "Error: Nemo env generation failed."
    exit 1
  }
  run_local_nemo_container "$env_local" "$nemo_data" || {
    echo "Error: local Nemo container start failed."
    exit 1
  }
  echo "Nemo deployed locally at http://localhost:${NEMO_HOST_PORT} (LEAN_API_URL uses host.docker.internal + devnet ports)."
  exit 0
fi

# --- Remote tooling server ---
remote_target="${TOOLING_SERVER_USER}@${TOOLING_SERVER}"
ssh_cmd="ssh -o StrictHostKeyChecking=no"
if [ -n "$sshKeyFile" ]; then
  key_path="$sshKeyFile"
  [[ "$key_path" == ~* ]] && key_path="${key_path/#\~/$HOME}"
  if [ -f "$key_path" ]; then
    ssh_cmd="ssh -i $key_path -o StrictHostKeyChecking=no"
  fi
fi

out_env=$(mktemp)
trap 'rm -f "$out_env"' EXIT
python3 "$convert_script" --write-nemo-env "$out_env" "$validator_config_file" || {
  echo "Error: Nemo env generation failed."
  exit 1
}

remote_env_dir=$(dirname "$REMOTE_NEMO_ENV_PATH")
$ssh_cmd "$remote_target" "mkdir -p $remote_env_dir $REMOTE_NEMO_DATA_DIR && rm -rf ${REMOTE_NEMO_DATA_DIR}/*"
rsync -e "$ssh_cmd" "$out_env" "${remote_target}:${REMOTE_NEMO_ENV_PATH}"

# Remote Docker: match tooling host arch when the registry publishes that variant in a multi-arch manifest.
remote_uname=$($ssh_cmd "$remote_target" "uname -m" | tr -d '\r')
remote_plat_args=$(nemo_docker_platform_args_for_machine "$remote_uname")

$ssh_cmd "$remote_target" "docker pull $remote_plat_args $NEMO_IMAGE && docker stop $NEMO_CONTAINER 2>/dev/null || true; docker rm -f $NEMO_CONTAINER 2>/dev/null || true; docker run -d --pull=always $remote_plat_args --name $NEMO_CONTAINER --restart unless-stopped -p ${NEMO_HOST_PORT}:5053 --env-file $REMOTE_NEMO_ENV_PATH -v $REMOTE_NEMO_DATA_DIR:/data $NEMO_IMAGE"

echo "Nemo deployed on $TOOLING_SERVER at port ${NEMO_HOST_PORT} (fresh DB under $REMOTE_NEMO_DATA_DIR, image $NEMO_IMAGE)."
