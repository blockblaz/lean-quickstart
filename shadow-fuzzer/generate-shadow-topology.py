#!/usr/bin/env python3
"""Generate Shadow topology with geo latencies and bandwidth tiers.

Usage:
  python3 generate-shadow-topology.py <node_count> <output_dir> [--seed SEED]
       [--regions-weights <json>] [--bandwidths-weights <json>] [--jitter <float>]

Produces:
  - topology.gml: graph with per-edge latencies
  - bandwidths.json: {"node_0": "50 Mbit", ...} bandwidth assignments
  - regions.json: {"node_0": "us-east", ...} region assignments
"""

import argparse
import json
import math
import random
import sys
from pathlib import Path

REGIONS_LATENCY_MS: dict[str, dict[str, int]] = {
    "us-east": {"us-east": 20, "us-west": 60, "europe": 80, "asia": 150, "sa": 120, "africa": 180},
    "us-west": {"us-east": 60, "us-west": 20, "europe": 130, "asia": 110, "sa": 160, "africa": 200},
    "europe": {"us-east": 80, "us-west": 130, "europe": 15, "asia": 100, "sa": 170, "africa": 80},
    "asia": {"us-east": 150, "us-west": 110, "europe": 100, "asia": 20, "sa": 250, "africa": 160},
    "sa": {"us-east": 120, "us-west": 160, "europe": 170, "asia": 250, "sa": 25, "africa": 220},
    "africa": {"us-east": 180, "us-west": 200, "europe": 80, "asia": 160, "sa": 220, "africa": 30},
}

DEFAULT_REGION_WEIGHTS = {
    "us-east": 0.30,
    "us-west": 0.15,
    "europe": 0.25,
    "asia": 0.20,
    "sa": 0.05,
    "africa": 0.05,
}

DEFAULT_BANDWIDTH_WEIGHTS = {
    "1 Gbit": 0.05,
    "100 Mbit": 0.20,
    "50 Mbit": 0.75,
}

DEFAULT_JITTER_RATIO = 0.3
DEFAULT_PACKET_LOSS = 0.0
LINK_PACKET_LOSS = 0.0


def weighted_choice(
    items: list[str], weights: list[float], rng: random.Random, count: int
) -> list[str]:
    total = sum(weights)
    probs = [w / total for w in weights]
    return rng.choices(items, weights=probs, k=count)


def assign_regions(
    node_count: int, region_weights: dict[str, float], rng: random.Random
) -> dict[str, str]:
    regions = list(region_weights.keys())
    weights = list(region_weights.values())
    assignments: dict[str, str] = {}
    for i in range(node_count):
        assignments[f"node_{i}"] = rng.choices(regions, weights=weights, k=1)[0]
    return assignments


def assign_bandwidths(
    node_count: int, bandwidth_weights: dict[str, float], rng: random.Random
) -> dict[str, str]:
    tiers = list(bandwidth_weights.keys())
    weights = list(bandwidth_weights.values())
    assignments: dict[str, str] = {}
    for i in range(node_count):
        assignments[f"node_{i}"] = rng.choices(tiers, weights=weights, k=1)[0]
    return assignments


def generate_gml(
    node_count: int,
    region_assignments: dict[str, str],
    bandwidth_assignments: dict[str, str],
    latency_ms: dict[str, dict[str, int]],
    jitter_ratio: float,
    rng: random.Random,
) -> str:
    lines: list[str] = ["graph [", "  directed 0"]

    for i in range(node_count):
        name = f"node_{i}"
        region = region_assignments[name]
        bw = bandwidth_assignments[name]
        lines.append("  node [")
        lines.append(f"    id {i}")
        lines.append(f'    host_bandwidth_up "{bw}"')
        lines.append(f'    host_bandwidth_down "{bw}"')
        lines.append(f'    label "{name}"')
        lines.append(f'    region "{region}"')
        lines.append("  ]")

    switch_id = node_count
    lines.append("  node [")
    lines.append(f"    id {switch_id}")
    lines.append('    host_bandwidth_up "10 Gbit"')
    lines.append('    host_bandwidth_down "10 Gbit"')
    lines.append('    label "switch"')
    lines.append("  ]")

    for i in range(node_count):
        lines.append("  edge [")
        lines.append(f"    source {i}")
        lines.append(f"    target {i}")
        lines.append('    latency "1 ms"')
        lines.append(f"    packet_loss {LINK_PACKET_LOSS}")
        lines.append("  ]")

    lines.append("  edge [")
    lines.append(f"    source {switch_id}")
    lines.append(f"    target {switch_id}")
    lines.append('    latency "1 ms"')
    lines.append(f"    packet_loss {LINK_PACKET_LOSS}")
    lines.append("  ]")

    for i in range(node_count):
        name = f"node_{i}"
        region = region_assignments[name]
        base_ms = latency_ms[region][region] * 0.5
        jitter = base_ms * jitter_ratio * (rng.random() * 2 - 1)
        latency = max(0.5, base_ms + jitter)

        lines.append("  edge [")
        lines.append(f"    source {i}")
        lines.append(f"    target {switch_id}")
        lines.append(f'    latency "{max(1, round(latency))} ms"')
        lines.append(f"    packet_loss {LINK_PACKET_LOSS}")
        lines.append("  ]")

    for i in range(node_count):
        name_i = f"node_{i}"
        region_i = region_assignments[name_i]
        for j in range(i + 1, node_count):
            name_j = f"node_{j}"
            region_j = region_assignments[name_j]

            base_ms = latency_ms[region_i].get(region_j, 200)
            jitter = base_ms * jitter_ratio * (rng.random() * 2 - 1)
            latency = max(0.5, base_ms + jitter)

            lines.append("  edge [")
            lines.append(f"    source {i}")
            lines.append(f"    target {j}")
            lines.append(f'    latency "{max(1, round(latency))} ms"')
            lines.append(f"    packet_loss {LINK_PACKET_LOSS}")
            lines.append("  ]")

    lines.append("]")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate Shadow topology with geo latencies"
    )
    parser.add_argument("node_count", type=int, help="Number of nodes")
    parser.add_argument("output_dir", type=str, help="Output directory")
    parser.add_argument("--seed", type=int, default=42, help="Random seed")
    parser.add_argument(
        "--region-weights",
        type=str,
        default=None,
        help="JSON dict of region weights",
    )
    parser.add_argument(
        "--bandwidth-weights",
        type=str,
        default=None,
        help="JSON dict of bandwidth weights",
    )
    parser.add_argument(
        "--jitter",
        type=float,
        default=DEFAULT_JITTER_RATIO,
        help="Latency jitter ratio",
    )
    parser.add_argument(
        "--latency-ms",
        type=str,
        default=None,
        help="JSON dict of region-to-region latency matrix",
    )
    args = parser.parse_args()

    rng = random.Random(args.seed)
    out = Path(args.output_dir)
    out.mkdir(parents=True, exist_ok=True)

    region_weights: dict[str, float]
    if args.region_weights:
        region_weights = json.loads(args.region_weights)
    else:
        region_weights = dict(DEFAULT_REGION_WEIGHTS)

    bandwidth_weights: dict[str, float]
    if args.bandwidth_weights:
        bandwidth_weights = json.loads(args.bandwidth_weights)
    else:
        bandwidth_weights = dict(DEFAULT_BANDWIDTH_WEIGHTS)

    latency_ms: dict[str, dict[str, int]]
    if args.latency_ms:
        latency_ms = json.loads(args.latency_ms)
    else:
        latency_ms = dict(REGIONS_LATENCY_MS)

    regions = assign_regions(args.node_count, region_weights, rng)
    bandwidths = assign_bandwidths(args.node_count, bandwidth_weights, rng)

    gml = generate_gml(args.node_count, regions, bandwidths, latency_ms, args.jitter, rng)
    gml_path = out / "topology.gml"
    gml_path.write_text(gml)
    print(f"Wrote {gml_path} ({args.node_count} nodes, {gml_path.stat().st_size} bytes)")

    bw_path = out / "bandwidths.json"
    bw_path.write_text(json.dumps(bandwidths, indent=2))
    print(f"Wrote {bw_path}")

    region_path = out / "regions.json"
    region_path.write_text(json.dumps(regions, indent=2))
    print(f"Wrote {region_path}")

    n_1gbit = sum(1 for b in bandwidths.values() if "Gbit" in b)
    region_counts: dict[str, int] = {}
    for r in regions.values():
        region_counts[r] = region_counts.get(r, 0) + 1
    print(
        f"Summary: {args.node_count} nodes, {n_1gbit} 1Gbit nodes, regions={region_counts}"
    )


if __name__ == "__main__":
    main()
