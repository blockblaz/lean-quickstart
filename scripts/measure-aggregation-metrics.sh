#!/usr/bin/env bash
# Scrape zeam aggregator Prometheus metrics and summarize aggregation performance.
#
# Usage:
#   scripts/measure-aggregation-metrics.sh [options]
#
# Options:
#   --validator-config PATH   (default: ansible-devnet/genesis/validator-config.yaml)
#   --nodes LIST              Comma-separated zeam node names (default: zeam aggregators)
#   --ssh-key PATH            (default: ~/.ssh/id_ed25519_github)
#   --ssh-user USER           (default: root)
#   --log-since DURATION      Docker log grep window per node (default: 30m)
#   --output FILE             Write JSON summary here (default: stdout only)
#   -h | --help

set -u
set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." &>/dev/null && pwd)"

VALIDATOR_CONFIG="${REPO_ROOT}/ansible-devnet/genesis/validator-config.yaml"
NODES_FILTER=""
SSH_KEY="${HOME}/.ssh/id_ed25519_github"
SSH_USER="root"
LOG_SINCE="30m"
OUTPUT_FILE=""

print_help() {
    sed -n '2,/^set -u/p' "${BASH_SOURCE[0]}" | sed -E 's/^# ?//' | sed -e '/^set -u/,$d'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --validator-config) VALIDATOR_CONFIG="$2"; shift 2 ;;
        --nodes)            NODES_FILTER="$2"; shift 2 ;;
        --ssh-key)          SSH_KEY="$2"; shift 2 ;;
        --ssh-user)         SSH_USER="$2"; shift 2 ;;
        --log-since)        LOG_SINCE="$2"; shift 2 ;;
        --output)           OUTPUT_FILE="$2"; shift 2 ;;
        -h|--help)          print_help; exit 0 ;;
        *)                  echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [[ ! -f "$VALIDATOR_CONFIG" ]]; then
    echo "validator config not found: $VALIDATOR_CONFIG" >&2
    exit 1
fi

export VALIDATOR_CONFIG NODES_FILTER
NODE_TABLE="$(python3 - <<'PY'
import os, sys
try:
    import yaml
except ImportError:
    sys.stderr.write("PyYAML required: pip install pyyaml\n")
    sys.exit(1)

cfg_path = os.environ["VALIDATOR_CONFIG"]
nodes_filter = os.environ.get("NODES_FILTER", "").strip()
want = set(x.strip() for x in nodes_filter.split(",") if x.strip()) if nodes_filter else None

with open(cfg_path) as f:
    cfg = yaml.safe_load(f)

validators = cfg.get("validators", cfg)
if isinstance(validators, dict):
    validators = validators.values()

rows = []
for v in validators:
    if not isinstance(v, dict):
        continue
    name = v.get("name", "")
    client = name.split("_")[0]
    if client != "zeam":
        continue
    if want is not None and name not in want:
        continue
    if not v.get("isAggregator", False):
        if want is None:
            continue
    ip = v["enrFields"]["ip"]
    port = v.get("metricsPort", 9102)
    rows.append((name, ip, port, bool(v.get("isAggregator", False))))

if not rows:
    sys.stderr.write("no matching zeam nodes\n")
    sys.exit(1)

for name, ip, port, agg in sorted(rows):
    print(f"{name}\t{ip}\t{port}\t{int(agg)}")
PY
)" || exit 1

histogram_quantile() {
    local quantile="$1"
    local metric_prefix="$2"
    local body="$3"
    python3 - "$quantile" "$metric_prefix" <<'PY' <<<"$body"
import sys
q = float(sys.argv[1])
prefix = sys.argv[2]
text = sys.stdin.read()
buckets = {}
count = 0
sum_v = 0.0
for line in text.splitlines():
    if not line.startswith(prefix + "_bucket"):
        if line.startswith(prefix + "_count"):
            count = int(float(line.rsplit(" ", 1)[-1]))
        elif line.startswith(prefix + "_sum"):
            sum_v = float(line.rsplit(" ", 1)[-1])
        continue
    le_part, val_s = line.rsplit(" ", 1)
    le = le_part.split("le=\"")[-1].rstrip("\"}")
    val = float(val_s)
    buckets[le] = val
if count == 0:
    print("n/a")
    sys.exit(0)
if not buckets:
    print(f"{sum_v/count:.3f}")
    sys.exit(0)
items = sorted(buckets.items(), key=lambda kv: float("inf") if kv[0] == "+Inf" else float(kv[0]))
target = q * count
prev_le = 0.0
prev_count = 0.0
for le_s, cum in items:
    le = float("inf") if le_s == "+Inf" else float(le_s)
    if cum >= target:
        if cum == prev_count:
            print(f"{le:.3f}")
        else:
            frac = (target - prev_count) / (cum - prev_count)
            est = prev_le + frac * (le - prev_le)
            print(f"{est:.3f}")
        break
    prev_le = le
    prev_count = cum
else:
    print(f"{sum_v/count:.3f}")
PY
}

counter_sum() {
    local prefix="$1"
    local body="$2"
    echo "$body" | awk -v p="$prefix" '$1 ~ "^"p"{s+=$NF} END{printf "%.0f", s+0}'
}

labeled_counter() {
    local prefix="$1"
    local body="$2"
    echo "$body" | awk -v p="$prefix" '$1 ~ "^"p"{"{print}' | sort
}

gauge_value() {
    local pattern="$1"
    local body="$2"
    echo "$body" | awk -v p="$pattern" '$1 ~ p {print $NF; exit}'
}

fetch_metrics() {
    local ip="$1"
    local port="$2"
    curl -sf --max-time 8 "http://${ip}:${port}/metrics" 2>/dev/null || true
}

fetch_remote_logs() {
    local ip="$1"
    local node="$2"
    ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new \
        "${SSH_USER}@${ip}" \
        "docker logs --since ${LOG_SINCE} zeam-${node} 2>&1 || docker logs --since ${LOG_SINCE} ${node} 2>&1 || true" 2>/dev/null || true
}

verify_image() {
    local ip="$1"
    local node="$2"
    ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new \
        "${SSH_USER}@${ip}" \
        "docker ps --format '{{.Names}} {{.Image}}' | grep -E '${node}|zeam-${node}' | head -1" 2>/dev/null || true
}

TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "=== Zeam aggregation metrics @ ${TS} ==="
echo "validator-config: ${VALIDATOR_CONFIG}"
echo "log window: ${LOG_SINCE}"
echo

JSON_LINES=()
JSON_LINES+=("{")
JSON_LINES+=("\"captured_at\": \"${TS}\",")
JSON_LINES+=("\"nodes\": [")

first_node=true
while IFS=$'\t' read -r node ip port is_agg; do
    [[ -z "$node" ]] && continue
    echo "--- ${node} (${ip}:${port}) aggregator=${is_agg} ---"

    image_line="$(verify_image "$ip" "$node")"
    if [[ -n "$image_line" ]]; then
        echo "container: ${image_line}"
    else
        echo "container: (not running or unreachable via SSH)"
    fi

    body="$(fetch_metrics "$ip" "$port")"
    if [[ -z "$body" ]]; then
        echo "metrics: UNREACHABLE"
        echo
        continue
    fi

    worker_p50="$(histogram_quantile 0.5 zeam_aggregate_worker_duration_seconds "$body")"
    worker_p95="$(histogram_quantile 0.95 zeam_aggregate_worker_duration_seconds "$body")"
    worker_count="$(counter_sum zeam_aggregate_worker_duration_seconds_count "$body")"
    worker_sum="$(echo "$body" | awk '/^zeam_aggregate_worker_duration_seconds_sum /{print $2; exit}')"
    build_p50="$(histogram_quantile 0.5 lean_pq_sig_aggregated_signatures_building_time_seconds "$body")"
    build_count="$(counter_sum lean_pq_sig_aggregated_signatures_building_time_seconds_count "$body")"
    publish_total="$(counter_sum zeam_aggregator_publish_aggregations_total "$body")"
    timely_cov="$(gauge_value 'lean_attestation_aggregate_coverage_validators\{section="timely",subnet="combined"\}' "$body")"
    late_cov="$(gauge_value 'lean_attestation_aggregate_coverage_validators\{section="late",subnet="combined"\}' "$body")"
    combined_cov="$(gauge_value 'lean_attestation_aggregate_coverage_validators\{section="combined",subnet="combined"\}' "$body")"

    echo "worker_duration_seconds: count=${worker_count} sum=${worker_sum:-0} p50=${worker_p50} p95=${worker_p95}"
    echo "building_time_seconds (wrap only): count=${build_count} p50=${build_p50}"
    echo "publish_aggregations_total: ${publish_total}"
    echo "coverage_validators (latest gauge): timely=${timely_cov:-?} late=${late_cov:-?} combined=${combined_cov:-?}"
    echo "aggregate_skip_total:"
    labeled_counter zeam_aggregate_skip_total "$body" | sed 's/^/  /'
    echo "building_phase_seconds (sum/count):"
    echo "$body" | awk '/^zeam_pq_sig_aggregated_signatures_building_phase_seconds_sum\{/{print "  "$0}' | sort
    echo "$body" | awk '/^zeam_pq_sig_aggregated_signatures_building_phase_seconds_count\{/{print "  "$0}' | sort

    logs="$(fetch_remote_logs "$ip" "$node")"
    agg_skips="$(echo "$logs" | grep -c 'skipping aggregation for slot=' || true)"
    att_skips="$(echo "$logs" | grep -c 'skipping attestation production for slot=' || true)"
    in_flight="$(echo "$logs" | grep -c 'already in flight' || true)"
    agg_starts="$(echo "$logs" | grep -c 'agg start slot=' || true)"
    trivial_drop="$(echo "$logs" | grep -c 'aggregator pre-filter: dropped' || true)"
    echo "logs (since ${LOG_SINCE}): agg_skip_lines=${agg_skips} in_flight=${in_flight} agg_start=${agg_starts} attestation_skip=${att_skips} trivial_pre_filter=${trivial_drop}"

    if [[ "$first_node" == false ]]; then
        JSON_LINES+=(",")
    fi
    first_node=false
    skip_json="$(labeled_counter zeam_aggregate_skip_total "$body" | python3 -c 'import sys,json; d={};
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    lbl=line.split("{reason=\"",1)[1].split("\"}",1)[0]
    d[lbl]=int(float(line.rsplit(" ",1)[-1]))
print(json.dumps(d))')"
    JSON_LINES+=("  {\"name\": \"${node}\", \"ip\": \"${ip}\", \"metrics_port\": ${port}, \"is_aggregator\": ${is_agg}, \"worker_count\": ${worker_count:-0}, \"worker_p50_s\": \"${worker_p50}\", \"worker_p95_s\": \"${worker_p95}\", \"publish_total\": ${publish_total:-0}, \"timely_coverage\": \"${timely_cov:-}\", \"late_coverage\": \"${late_cov:-}\", \"combined_coverage\": \"${combined_cov:-}\", \"log_agg_skips\": ${agg_skips}, \"log_in_flight\": ${in_flight}, \"log_agg_starts\": ${agg_starts}, \"log_att_skips\": ${att_skips}, \"aggregate_skip\": ${skip_json}}")
    echo
done <<<"$NODE_TABLE"

JSON_LINES+=("]")
JSON_LINES+=("}")

if [[ -n "$OUTPUT_FILE" ]]; then
    printf '%s\n' "${JSON_LINES[@]}" >"$OUTPUT_FILE"
    echo "Wrote ${OUTPUT_FILE}"
fi
