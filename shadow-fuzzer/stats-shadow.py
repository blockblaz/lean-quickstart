#!/usr/bin/env python3
"""Parse Shadow simulation output and emit stats.json with propagation data.

Reads shadow.data host stdout/stderr logs, plus regions.json, bandwidths.json,
and run-metadata.json (passed via --metadata-json), then writes a single stats.json
with the resolved run configuration embedded.

Handles both:
  - qlean LEAN-INTEROP-TEST structured events
  - zeam text-pattern gossip log lines (best-effort fallback)

Usage:
  python3 stats-shadow.py <run_dir> --metadata-json <path>
"""

import json
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any

SHADOW_TS_RE = re.compile(
    r"\d+\.\d+\.\d+\s+(\d+):(\d+):(\d+)\.(\d+)"
)


def parse_shadow_timestamp(line: str) -> float:
    m = SHADOW_TS_RE.search(line)
    if m:
        h, mi, s, us = m.groups()
        return int(h) * 3600 + int(mi) * 60 + int(s) + int(us) / 1_000_000
    return 0.0


def _parse_interop_attestation(line: str) -> dict[str, Any] | None:
    m = re.search(
        r'\["LEAN-INTEROP-TEST",\s*(\d+),\s*"RECEIVE-ATTESTATION",\s*\[(\d+),\s*\[([^\]]+)\]',
        line,
    )
    if not m:
        return None
    ts_ms = int(m.group(1))
    validator_id = int(m.group(2))
    inner = m.group(3).strip()
    parts = [p.strip().strip('"') for p in inner.split(",")]
    if len(parts) < 5:
        return None
    return {
        "ts_ms": ts_ms,
        "validator_id": validator_id,
        "source_slot": int(parts[0]),
        "target_slot": int(parts[1]),
        "head_slot": int(parts[2]),
        "slot": int(parts[3]),
        "block_hash": parts[4],
    }


def _parse_interop_publish_block(line: str) -> dict[str, Any] | None:
    m = re.search(
        r'\["LEAN-INTEROP-TEST",\s*(\d+),\s*"PUBLISH-BLOCK",\s*(\{.+\})\]', line
    )
    if not m:
        return None
    ts_ms = int(m.group(1))
    payload = m.group(2)
    slot_m = re.search(r'"slot":\s*(\d+)', payload)
    hash_m = re.search(r'"hash":\s*"([0-9a-f]+)"', payload)
    proposer_m = re.search(r'"proposer":\s*(\d+)', payload)
    if not slot_m:
        return None
    return {
        "ts_ms": ts_ms,
        "slot": int(slot_m.group(1)),
        "block_hash": hash_m.group(1) if hash_m else "",
        "proposer": int(proposer_m.group(1)) if proposer_m else 0,
    }


def _parse_interop_publish_attestation(line: str) -> dict[str, Any] | None:
    m = re.search(
        r'\["LEAN-INTEROP-TEST",\s*(\d+),\s*"PUBLISH-ATTESTATION",\s*\[(\d+),\s*\[([^\]]+)\]',
        line,
    )
    if not m:
        return None
    ts_ms = int(m.group(1))
    validator_id = int(m.group(2))
    inner = m.group(3).strip()
    parts = [p.strip().strip('"') for p in inner.split(",")]
    if len(parts) < 4:
        return None
    return {
        "ts_ms": ts_ms,
        "validator_id": validator_id,
        "slot": int(parts[3]),
    }


def _parse_zeam_receive_attestation(line: str) -> dict[str, Any] | None:
    m = re.search(
        r"received gossip attestation for slot=(\d+)\s+validator=(\d+)", line
    )
    if not m:
        return None
    return {
        "ts": parse_shadow_timestamp(line),
        "slot": int(m.group(1)),
        "validator_id": int(m.group(2)),
    }


def _parse_zeam_receive_block(line: str) -> dict[str, Any] | None:
    m = re.search(
        r"received gossip block for slot=(\d+)\s+.*?proposer=(\d+)", line
    )
    if not m:
        return None
    return {
        "ts": parse_shadow_timestamp(line),
        "slot": int(m.group(1)),
        "proposer": int(m.group(2)),
    }


def _parse_zeam_publish_block(line: str) -> dict[str, Any] | None:
    m = re.search(
        r"published block to network:\s+slot=(\d+)\s+proposer=(\d+)", line
    )
    if not m:
        return None
    return {
        "ts": parse_shadow_timestamp(line),
        "slot": int(m.group(1)),
        "proposer": int(m.group(2)),
    }


def _parse_zeam_publish_attestation(line: str) -> dict[str, Any] | None:
    m = re.search(
        r"published attestation to network:\s+slot=(\d+)\s+validator=(\d+)", line
    )
    if not m:
        return None
    return {
        "ts": parse_shadow_timestamp(line),
        "slot": int(m.group(1)),
        "validator_id": int(m.group(2)),
    }


def _read_host_events(
    hosts_dir: Path,
) -> dict[str, dict[str, list[dict[str, Any]]]]:
    def _host_file_lines(host_name: str):
        host_dir = hosts_dir / host_name
        for stdout_file in sorted(host_dir.glob("*.stdout")):
            with open(stdout_file, errors="replace") as f:
                for line in f:
                    yield host_name, line.rstrip("\n")
        for stderr_file in sorted(host_dir.glob("*.stderr")):
            with open(stderr_file, errors="replace") as f:
                for line in f:
                    yield host_name, line.rstrip("\n")

    def _append(kind: str, host: str, evt: dict[str, Any]):
        evt["host"] = host
        events[kind][host].append(evt)

    events: dict[str, dict[str, list[dict[str, Any]]]] = {
        "receive_attestation": defaultdict(list),
        "receive_block": defaultdict(list),
        "publish_block": defaultdict(list),
        "publish_attestation": defaultdict(list),
    }

    for host_dir in sorted(hosts_dir.iterdir()):
        if not host_dir.is_dir():
            continue
        for host_name, line in _host_file_lines(host_dir.name):
            if "LEAN-INTEROP-TEST" in line:
                if "RECEIVE-ATTESTATION" in line:
                    e = _parse_interop_attestation(line)
                    if e:
                        _append("receive_attestation", host_name, e)
                elif "PUBLISH-BLOCK" in line:
                    e = _parse_interop_publish_block(line)
                    if e:
                        _append("publish_block", host_name, e)
                elif "PUBLISH-ATTESTATION" in line:
                    e = _parse_interop_publish_attestation(line)
                    if e:
                        _append("publish_attestation", host_name, e)
            else:
                if "received gossip attestation for slot=" in line:
                    e = _parse_zeam_receive_attestation(line)
                    if e:
                        _append("receive_attestation", host_name, e)
                elif "received gossip block for slot=" in line:
                    e = _parse_zeam_receive_block(line)
                    if e:
                        _append("receive_block", host_name, e)
                elif "published block to network:" in line:
                    e = _parse_zeam_publish_block(line)
                    if e:
                        _append("publish_block", host_name, e)
                elif "published attestation to network:" in line:
                    e = _parse_zeam_publish_attestation(line)
                    if e:
                        _append("publish_attestation", host_name, e)

    return events


def _compute_attestation_slot_stats(
    events: dict[str, dict[str, list[dict[str, Any]]]],
    genesis_ms: int,
) -> dict[str, Any]:
    ra = events["receive_attestation"]
    if not ra:
        return {"slots": [], "summary": {"warning": "No attestation receive events found"}}

    slot_publishers: dict[int, set[int]] = defaultdict(set)
    for host_events in ra.values():
        for evt in host_events:
            slot_publishers[evt["slot"]].add(evt.get("validator_id", 0))

    slot_stats_list: list[dict[str, Any]] = []

    for slot in sorted(slot_publishers.keys()):
        n_publishers = len(slot_publishers[slot])
        if n_publishers < 2:
            continue

        node_times_ms: list[float] = []
        for host_name, host_events in ra.items():
            received: dict[int, float] = {}
            for evt in host_events:
                if evt["slot"] != slot:
                    continue
                ts_val = evt.get("ts_ms", evt.get("ts", 0) * 1000)
                offset = ts_val - genesis_ms
                vid = evt.get("validator_id", 0)
                if vid not in received or offset < received[vid]:
                    received[vid] = offset

            if len(received) < 2:
                continue

            times = sorted(received.values())
            idx = min(len(times) - 1, int(0.95 * n_publishers) - 1)
            node_times_ms.append(times[idx] - times[0])

        if node_times_ms:
            s = sorted(node_times_ms)
            n = len(s)
            slot_stats_list.append(
                {
                    "slot": slot,
                    "n_publishers": n_publishers,
                    "n_measurements": n,
                    "p50_ms": round(s[n // 2], 1),
                    "p95_ms": round(s[int(0.95 * (n - 1))], 1) if n > 1 else round(s[0], 1),
                    "p99_ms": round(s[int(0.99 * (n - 1))], 1) if n > 1 else round(s[0], 1),
                    "max_ms": round(s[-1], 1),
                    "mean_ms": round(sum(s) / n, 1),
                }
            )

    summary: dict[str, Any] = {}
    if slot_stats_list:
        all_p99 = [s["p99_ms"] for s in slot_stats_list]
        all_p99.sort()
        summary["slots_with_data"] = len(slot_stats_list)
        summary["aggregate_p99_ms"] = round(
            all_p99[min(int(0.99 * len(all_p99)), len(all_p99) - 1)], 1
        )
        summary["aggregate_p50_ms"] = round(all_p99[len(all_p99) // 2], 1)
    else:
        summary["warning"] = "Insufficient data for per-slot attestation stats"

    return {"slots": slot_stats_list, "summary": summary}


def _compute_block_slot_stats(
    events: dict[str, dict[str, list[dict[str, Any]]]],
    genesis_ms: int,
) -> dict[str, Any]:
    pb = events["publish_block"]
    rb = events["receive_block"]

    block_slots: dict[int, dict[str, Any]] = {}
    for host_events in pb.values():
        for evt in host_events:
            slot = evt["slot"]
            block_slots[slot] = {
                "slot": slot,
                "proposer": evt.get("proposer", 0),
                "block_hash": evt.get("block_hash", ""),
                "published": True,
                "receive_timestamps_ms": {},
            }

    if rb:
        for host_name, host_events in rb.items():
            for evt in host_events:
                slot = evt["slot"]
                if slot not in block_slots:
                    block_slots[slot] = {
                        "slot": slot,
                        "proposer": evt.get("proposer", 0),
                        "block_hash": "",
                        "published": False,
                        "receive_timestamps_ms": {},
                    }
                ts_val = evt.get("ts_ms", evt.get("ts", 0) * 1000)
                block_slots[slot]["receive_timestamps_ms"][host_name] = round(
                    ts_val - genesis_ms, 1
                )

    slot_list: list[dict[str, Any]] = []
    for slot in sorted(block_slots.keys()):
        s = block_slots[slot]
        reception = s.get("receive_timestamps_ms", {})
        slot_d = {
            "slot": slot,
            "proposer": s["proposer"],
            "published": s["published"],
        }
        if reception:
            times = sorted(reception.values())
            slot_d["first_receive_ms"] = times[0]
            slot_d["last_receive_ms"] = times[-1]
            slot_d["n_received"] = len(times)
            slot_d["receive_timestamps_ms"] = reception
        slot_list.append(slot_d)

    summary: dict[str, Any] = {}
    if slot_list:
        published = [s for s in slot_list if s["published"]]
        received = [s for s in slot_list if "first_receive_ms" in s]
        summary["n_published"] = len(published)
        summary["n_received"] = len(received)
    else:
        summary["warning"] = "No block events found"

    return {"slots": slot_list, "summary": summary}


def _load_json(path: Path) -> dict[str, Any]:
    if path.is_file():
        return json.loads(path.read_text())
    return {}


def collect_stats(run_dir: str, metadata: dict[str, Any] | None = None) -> dict[str, Any]:
    run_path = Path(run_dir)
    if not run_path.is_dir():
        print(f"ERROR: {run_dir} is not a directory", file=sys.stderr)
        sys.exit(1)

    if metadata is None:
        metadata = {}

    warnings: list[str] = []

    regions = _load_json(run_path / "regions.json")
    bandwidths = _load_json(run_path / "bandwidths.json")

    hosts_dir = run_path / "shadow.data" / "hosts"
    if not hosts_dir.is_dir():
        hosts_dir = run_path / "hosts"
    if not hosts_dir.is_dir():
        warnings.append("shadow.data/hosts directory not found; no propagation stats available")
        result: dict[str, Any] = {
            "node_distribution": {
                "regions": {},
                "bandwidths": {},
                "clients": metadata.get("node_counts", {}),
            },
            "blocks": {"slots": [], "summary": {"warning": warnings[0]}},
            "attestations": {"slots": [], "summary": {"warning": warnings[0]}},
            "warnings": warnings,
        }
        for key in ("run_id", "run_index", "fuzzer", "simulation", "clients", "node_counts"):
            if key in metadata:
                result[key] = metadata[key]
        return result

    events = _read_host_events(hosts_dir)

    total_receive_att = sum(len(v) for v in events["receive_attestation"].values())
    total_receive_block = sum(len(v) for v in events["receive_block"].values())
    print(
        f"Events: {total_receive_att} attestation receives, "
        f"{total_receive_block} block receives"
    )

    if total_receive_att == 0 and total_receive_block == 0:
        warnings.append("No propagation events found in any host stdout/stderr")

    genesis_ms = 0
    for host_events in events["receive_attestation"].values():
        for evt in host_events:
            ts_val = evt.get("ts_ms", evt.get("ts", 0) * 1000)
            if genesis_ms == 0 or ts_val < genesis_ms:
                genesis_ms = ts_val
    genesis_ms = (genesis_ms // 1_000_000) * 1_000_000

    attestation_stats = _compute_attestation_slot_stats(events, int(genesis_ms))
    block_stats = _compute_block_slot_stats(events, int(genesis_ms))

    region_counts: dict[str, int] = {}
    for r in regions.values():
        region_counts[r] = region_counts.get(r, 0) + 1

    bw_counts: dict[str, int] = {}
    for b in bandwidths.values():
        bw_counts[b] = bw_counts.get(b, 0) + 1

    node_counts = metadata.get("node_counts", {})

    result: dict[str, Any] = {
        "blocks": block_stats,
        "attestations": attestation_stats,
        "node_distribution": {
            "clients": node_counts,
            "regions": region_counts,
            "bandwidths": bw_counts,
        },
        "warnings": warnings,
    }

    for key in ("run_id", "run_index", "fuzzer", "simulation", "clients", "node_counts"):
        if key in metadata:
            result[key] = metadata[key]

    return result


def main() -> None:
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <run_dir> [--metadata-json <path>]", file=sys.stderr)
        sys.exit(1)

    run_dir = sys.argv[1]
    metadata: dict[str, Any] = {}
    try:
        idx = sys.argv.index("--metadata-json")
        metadata_path = Path(sys.argv[idx + 1])
        if metadata_path.is_file():
            metadata = json.loads(metadata_path.read_text())
    except (ValueError, IndexError):
        pass

    stats = collect_stats(run_dir, metadata)

    stats_path = Path(run_dir) / "stats.json"
    with open(stats_path, "w") as f:
        json.dump(stats, f, indent=2)
    print(f"Wrote {stats_path}")


if __name__ == "__main__":
    main()
