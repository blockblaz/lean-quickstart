#!/usr/bin/env bash
# Collect Docker logs and runtime metadata from every devnet validator host,
# fetch them in parallel to the local machine, and bundle the result into a
# single timestamped tar.gz under ./tmp/.
#
# Host list defaults to ansible-devnet/genesis/validator-config.yaml (each
# validator's enrFields.ip). Use --inventory to use Ansible inventory instead.
#
# Usage:
#   scripts/collect-devnet-logs.sh [options]
#
# Options:
#   --validator-config PATH
#                      Validator config YAML (default: ansible-devnet/genesis/validator-config.yaml)
#   --inventory PATH   Use Ansible inventory for node list and ansible_host instead
#                      of validator-config (disables validator-config default)
#   --nodes LIST       Comma-separated subset of node names
#                      (default: all validators / all inventory nodes)
#   --since DURATION   Only include log entries newer than DURATION
#                      (e.g. "2h", "30m", "2026-04-23T00:00:00"; default: unset = full log)
#   --tail N           Only include the last N log lines per node
#                      (default: unset = full log)
#   --output DIR       Directory to place the bundle and staging data in
#                      (default: ./tmp)
#   --keep-staging     Do not delete the per-node staging directory after bundling
#   --jobs N           Parallel SSH fan-out (default: 8)
#   --ssh-key PATH     Private key used to authenticate over SSH
#                      (default: ~/.ssh/id_ed25519_github)
#   --ssh-user USER    Remote login user
#                      (default: root)
#   -h | --help        Show this help
#
# The bundle layout is:
#   devnet-logs-<TIMESTAMP>/
#     manifest.txt                   # nodes + hosts + capture time
#     <node_name>/
#       docker.log                   # `docker logs` stdout+stderr, with timestamps
#       docker-inspect.json          # `docker inspect <container>`
#       docker-ps.txt                # `docker ps -a` on the host
#       ssh.log                      # any SSH-level errors for this node
#
# Requires locally: bash, ssh, tar, python3, PyYAML (to parse YAML).
# Requires on each remote host: docker.

set -u
set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." &>/dev/null && pwd)"

USE_INVENTORY=false
VALIDATOR_CONFIG="${REPO_ROOT}/ansible-devnet/genesis/validator-config.yaml"
INVENTORY="${REPO_ROOT}/ansible/inventory/hosts.yml"
NODES_FILTER=""
SINCE=""
TAIL=""
OUTPUT_DIR="${REPO_ROOT}/tmp"
KEEP_STAGING=false
JOBS=8
SSH_KEY_DEFAULT="${HOME}/.ssh/id_ed25519_github"
SSH_USER_DEFAULT="root"

print_help() {
    sed -n '2,/^set -u/p' "${BASH_SOURCE[0]}" | sed -E 's/^# ?//' | sed -e '/^set -u/,$d'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --validator-config) VALIDATOR_CONFIG="$2"; USE_INVENTORY=false; shift 2 ;;
        --inventory)        INVENTORY="$2"; USE_INVENTORY=true; shift 2 ;;
        --nodes)        NODES_FILTER="$2"; shift 2 ;;
        --since)        SINCE="$2"; shift 2 ;;
        --tail)         TAIL="$2"; shift 2 ;;
        --output)       OUTPUT_DIR="$2"; shift 2 ;;
        --keep-staging) KEEP_STAGING=true; shift ;;
        --jobs)         JOBS="$2"; shift 2 ;;
        --ssh-key)      SSH_KEY_DEFAULT="$2"; shift 2 ;;
        --ssh-user)     SSH_USER_DEFAULT="$2"; shift 2 ;;
        -h|--help)      print_help; exit 0 ;;
        *)              echo "unknown argument: $1" >&2; print_help >&2; exit 2 ;;
    esac
done

if ${USE_INVENTORY}; then
    if [[ ! -f "${INVENTORY}" ]]; then
        echo "inventory not found: ${INVENTORY}" >&2
        exit 1
    fi
else
    if [[ ! -f "${VALIDATOR_CONFIG}" ]]; then
        echo "validator config not found: ${VALIDATOR_CONFIG}" >&2
        exit 1
    fi
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required (used to parse YAML)" >&2
    exit 1
fi

if [[ ! -f "${SSH_KEY_DEFAULT}" ]]; then
    echo "ssh key not found: ${SSH_KEY_DEFAULT}" >&2
    echo "pass --ssh-key PATH to override" >&2
    exit 1
fi

# Extract "<node>\t<user>\t<host>\t<ssh_key>" lines (user/key columns are ignored
# for SSH; collect_one uses --ssh-user / --ssh-key). Source: validator-config
# or Ansible inventory depending on USE_INVENTORY.
NODES_TSV="$(
    INVENTORY_PATH="${INVENTORY}" \
    VALIDATOR_CONFIG_PATH="${VALIDATOR_CONFIG}" \
    USE_INVENTORY="${USE_INVENTORY}" \
    NODES_FILTER="${NODES_FILTER}" \
    python3 - <<'PY'
import os, sys
try:
    import yaml
except ImportError as exc:
    sys.stderr.write(f"PyYAML not available ({exc}); pip install pyyaml\n")
    sys.exit(1)

nodes_filter = {n.strip() for n in os.environ.get("NODES_FILTER", "").split(",") if n.strip()}
use_inventory = os.environ.get("USE_INVENTORY", "false").lower() in ("1", "true", "yes")
rows: list[str] = []

if use_inventory:
    inventory_path = os.environ["INVENTORY_PATH"]
    with open(inventory_path, "r") as f:
        data = yaml.safe_load(f)
    children = data.get("all", {}).get("children", {}) or {}
    for group_name, group in children.items():
        if group_name in ("local", "bootnodes"):
            continue
        for node_name, node_vars in (group.get("hosts") or {}).items():
            host = node_vars.get("ansible_host")
            user = node_vars.get("ansible_user") or os.environ.get("USER", "root")
            key = node_vars.get("ansible_ssh_private_key_file") or ""
            if not host:
                continue
            if nodes_filter and node_name not in nodes_filter:
                continue
            rows.append("\t".join([node_name, user, host, key]))
else:
    vc_path = os.environ["VALIDATOR_CONFIG_PATH"]
    with open(vc_path, "r") as f:
        data = yaml.safe_load(f)
    for v in data.get("validators") or []:
        node_name = v.get("name")
        enr = v.get("enrFields") or {}
        host = enr.get("ip")
        if not node_name or not host:
            continue
        if nodes_filter and node_name not in nodes_filter:
            continue
        rows.append("\t".join([str(node_name), "_", str(host), ""]))

for row in rows:
    print(row)
PY
)"

if [[ -z "${NODES_TSV}" ]]; then
    echo "no nodes matched (filter='${NODES_FILTER}')" >&2
    exit 1
fi

TIMESTAMP="$(date -u +"%Y%m%dT%H%M%SZ")"
BUNDLE_NAME="devnet-logs-${TIMESTAMP}"
STAGING_DIR="${OUTPUT_DIR}/${BUNDLE_NAME}"
BUNDLE_PATH="${OUTPUT_DIR}/${BUNDLE_NAME}.tar.gz"

mkdir -p "${STAGING_DIR}"

# Build a compact manifest up front so we have context even if the run aborts.
{
    echo "bundle: ${BUNDLE_NAME}"
    echo "captured_at_utc: ${TIMESTAMP}"
    echo "captured_from: $(hostname)"
    if ${USE_INVENTORY}; then
        echo "node_source: inventory"
        echo "inventory: ${INVENTORY}"
    else
        echo "node_source: validator-config"
        echo "validator_config: ${VALIDATOR_CONFIG}"
    fi
    echo "since: ${SINCE:-<full log>}"
    echo "tail: ${TAIL:-<full log>}"
    echo "parallel_jobs: ${JOBS}"
    echo ""
    printf "%-14s %-6s %s\n" "NODE" "USER" "HOST"
    printf "%-14s %-6s %s\n" "----" "----" "----"
    while IFS=$'\t' read -r node user host _key; do
        [[ -z "${node}" ]] && continue
        printf "%-14s %-6s %s\n" "${node}" "${user}" "${host}"
    done <<<"${NODES_TSV}"
} >"${STAGING_DIR}/manifest.txt"

# Assemble the remote command. We always stream everything to stdout on the
# remote, wrapped in `--- BEGIN/END <section> ---` markers; the local side
# splits it back into per-file artifacts. This keeps the SSH invocation to a
# single round-trip per node.
DOCKER_LOGS_CMD="docker logs --timestamps"
[[ -n "${SINCE}" ]] && DOCKER_LOGS_CMD+=" --since '${SINCE}'"
[[ -n "${TAIL}"  ]] && DOCKER_LOGS_CMD+=" --tail '${TAIL}'"

# Per-node fetcher. Runs in a subshell so it can be backgrounded by xargs.
collect_one() {
    local tsv_line="$1"
    IFS=$'\t' read -r node user host key <<<"${tsv_line}"
    [[ -z "${node}" ]] && return 0

    # Always log in as root with the GitHub SSH key, regardless of inventory
    # overrides or the caller's SSH agent state.
    user="${SSH_USER_DEFAULT}"
    key="${SSH_KEY_DEFAULT}"

    local node_dir="${STAGING_DIR}/${node}"
    mkdir -p "${node_dir}"

    local ssh_opts=(
        -o BatchMode=yes
        -o ConnectTimeout=10
        -o StrictHostKeyChecking=accept-new
        -o UserKnownHostsFile=/dev/null
        -o LogLevel=ERROR
        -o ServerAliveInterval=30
        -o IdentitiesOnly=yes
    )
    [[ -n "${key}" ]] && ssh_opts+=(-i "${key}")

    local remote_script
    remote_script=$(cat <<REMOTE
set -u
echo "--- BEGIN docker-ps ---"
docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>&1 || true
echo "--- END docker-ps ---"
echo "--- BEGIN docker-inspect ---"
docker inspect '${node}' 2>&1 || true
echo "--- END docker-inspect ---"
echo "--- BEGIN docker-log ---"
${DOCKER_LOGS_CMD} '${node}' 2>&1 || true
echo "--- END docker-log ---"
REMOTE
)

    local raw="${node_dir}/.raw.out"
    if ! ssh "${ssh_opts[@]}" "${user}@${host}" "${remote_script}" \
            >"${raw}" 2>"${node_dir}/ssh.log"; then
        echo "[${node}] ssh to ${user}@${host} failed (see ssh.log)" >&2
    fi

    # Split the single stream back into per-section files, stripping markers.
    python3 - "${raw}" "${node_dir}" <<'SPLIT'
import sys, os, re
raw_path, out_dir = sys.argv[1], sys.argv[2]
sections = {
    "docker-ps":      "docker-ps.txt",
    "docker-inspect": "docker-inspect.json",
    "docker-log":     "docker.log",
}
try:
    with open(raw_path, "r", errors="replace") as f:
        text = f.read()
except FileNotFoundError:
    sys.exit(0)
for tag, fname in sections.items():
    m = re.search(
        rf"^--- BEGIN {re.escape(tag)} ---\n(.*?)^--- END {re.escape(tag)} ---\n",
        text,
        flags=re.MULTILINE | re.DOTALL,
    )
    out_path = os.path.join(out_dir, fname)
    with open(out_path, "w") as f:
        f.write(m.group(1) if m else "")
os.remove(raw_path)
SPLIT

    local log_size="?"
    if [[ -f "${node_dir}/docker.log" ]]; then
        log_size=$(wc -c <"${node_dir}/docker.log" | tr -d ' ')
    fi
    echo "[${node}] captured (log bytes=${log_size})"
}

NODE_COUNT="$(printf '%s\n' "${NODES_TSV}" | wc -l | tr -d ' ')"
echo "Collecting logs for ${NODE_COUNT} node(s) -> ${STAGING_DIR}"

# Fan out across nodes with bounded parallelism using background jobs. On
# macOS's bash 3.2 there is no `wait -n`, so we run in fixed-size waves of
# ${JOBS} and `wait` for each wave to drain before starting the next one.
wave=()
flush_wave() {
    # macOS bash 3.2 + `set -u` does not tolerate `${wave[@]}` when `wave`
    # has never been assigned, so guard both the count check and the
    # expansion with the `${var+...}` / `${var[@]-}` defaults.
    if [[ "${#wave[@]}" -eq 0 ]]; then
        return 0
    fi
    local pid
    for pid in "${wave[@]}"; do
        wait "${pid}" || true
    done
    wave=()
}

while IFS= read -r tsv_line; do
    [[ -z "${tsv_line}" ]] && continue
    collect_one "${tsv_line}" &
    wave+=("$!")
    if (( ${#wave[@]} >= JOBS )); then
        flush_wave
    fi
done <<<"${NODES_TSV}"
flush_wave

# Build the tarball. Working directly in ${OUTPUT_DIR} keeps the leading path
# component inside the archive equal to the bundle name.
( cd "${OUTPUT_DIR}" && tar -czf "${BUNDLE_NAME}.tar.gz" "${BUNDLE_NAME}" )

if ! ${KEEP_STAGING}; then
    rm -rf "${STAGING_DIR}"
fi

BUNDLE_SIZE=$(du -h "${BUNDLE_PATH}" | awk '{print $1}')
echo ""
echo "Bundle:    ${BUNDLE_PATH}"
echo "Size:      ${BUNDLE_SIZE}"
if ${KEEP_STAGING}; then
    echo "Staging:   ${STAGING_DIR}"
fi
