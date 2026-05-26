#!/usr/bin/env python3
"""Shadow Fuzzer — randomized reproducible Shadow simulation sweeps.

Reads a template config.toml with optional {min, max} range values, generates
per-run concrete configs with deterministic sampling, and runs Shadow
simulations either locally or inside a Docker ARM container.

Usage:
  python3 shadow-fuzzer.py [config.toml]
  python3 shadow-fuzzer.py --dry-run config.example.toml
"""

from __future__ import annotations

import json
import os
import random
import secrets
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

try:
    import tomllib
except ImportError:
    import tomli as tomllib  # type: ignore

import yaml

FUZZER_ROOT = Path(__file__).resolve().parent
REPO_ROOT = FUZZER_ROOT.parent
SHADOW_EPOCH = 946684800
SHADOW_GENESIS_TIME = 946684860

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


def _resolve_value(raw: Any, rng: random.Random) -> Any:
    if isinstance(raw, dict) and "min" in raw and "max" in raw:
        lo = raw["min"]
        hi = raw["max"]
        if isinstance(lo, int) and isinstance(hi, int):
            return rng.randint(lo, hi)
        return lo + rng.random() * (hi - lo)
    return raw


def _resolve_weight_table(
    raw: dict[str, Any], rng: random.Random
) -> dict[str, float]:
    resolved: dict[str, float] = {}
    for key, val in raw.items():
        resolved[key] = float(_resolve_value(val, rng))
    total = sum(resolved.values())
    if total > 0:
        for k in resolved:
            resolved[k] /= total
    return resolved


def _sample_clients(
    client_weights: dict[str, float], total_nodes: int, rng: random.Random
) -> tuple[list[str], dict[str, int]]:
    names = list(client_weights.keys())
    probs = [client_weights[n] for n in names]
    sampled = rng.choices(names, weights=probs, k=total_nodes)
    counts: dict[str, int] = {}
    for c in sampled:
        counts[c] = counts.get(c, 0) + 1
    return sampled, counts


def _generate_privkey(rng: random.Random) -> str:
    return secrets.token_hex(32)


def _write_validator_config(
    run_dir: Path,
    client_list: list[str],
    total_subnets: int,
    aggregators_per_subnet: int,
    rng: random.Random,
) -> None:
    genesis_dir = run_dir / "genesis"
    genesis_dir.mkdir(parents=True, exist_ok=True)

    validators: list[dict[str, Any]] = []
    host_index = 0
    client_indices: dict[str, int] = {}

    for client in client_list:
        idx = client_indices.get(client, 0)
        client_indices[client] = idx + 1
        name = f"{client}_{idx}"
        validators.append(
            {
                "name": name,
                "privkey": _generate_privkey(rng),
                "enrFields": {
                    "ip": f"100.0.0.{host_index + 1}",
                    "quic": 9001 + host_index,
                },
                "metricsPort": 8081 + host_index,
                "apiPort": 5052,
                "isAggregator": False,
                "count": 1,
            }
        )
        host_index += 1

    subnet_buckets: dict[int, list[int]] = {}
    for i, _ in enumerate(validators):
        subnet = i % total_subnets
        subnet_buckets.setdefault(subnet, []).append(i)

    for subnet in range(total_subnets):
        candidates = subnet_buckets.get(subnet, [])
        n_select = min(aggregators_per_subnet, len(candidates))
        selected = rng.sample(candidates, n_select) if n_select else []
        for idx in selected:
            validators[idx]["isAggregator"] = True

    config = {
        "shuffle": "roundrobin",
        "deployment_mode": "local",
        "config": {
            "activeEpoch": 18,
            "keyType": "hash-sig",
            "attestation_committee_count": total_subnets,
        },
        "validators": validators,
    }

    vc_path = genesis_dir / "validator-config.yaml"
    with open(vc_path, "w") as f:
        yaml.dump(config, f, default_flow_style=False, sort_keys=False)
    print(f"  Wrote {vc_path}")



def _resolve_config(template: dict[str, Any], run_index: int) -> dict[str, Any]:
    template_seed = template["fuzzer"]["seed"]
    seed = template_seed + run_index
    rng = random.Random(seed)

    fuzzer_raw = template["fuzzer"]
    simulation_raw = template.get("simulation", {})
    clients_raw = template.get("clients", {})
    network_raw = template.get("network", {})

    duration_secs = _resolve_value(fuzzer_raw["duration_secs"], rng)
    runner = _resolve_value(fuzzer_raw["runner"], rng)

    total_nodes = int(_resolve_value(simulation_raw["total_nodes"], rng))
    total_subnets = int(_resolve_value(simulation_raw["total_subnets"], rng))
    aggregators_per_subnet = int(
        _resolve_value(simulation_raw.get("aggregators_per_subnet", 1), rng)
    )
    sig_agg_rate = float(
        _resolve_value(
            simulation_raw.get("signatures_aggregation_rate", 22.704), rng
        )
    )
    rec_agg_rate = float(
        _resolve_value(
            simulation_raw.get("recursive_aggregation_rate", 0.0), rng
        )
    )

    client_weights = _resolve_weight_table(clients_raw, rng)
    client_list, node_counts = _sample_clients(client_weights, total_nodes, rng)

    region_weights = _resolve_weight_table(
        network_raw.get("regions", DEFAULT_REGION_WEIGHTS), rng
    )
    bandwidth_weights = _resolve_weight_table(
        network_raw.get("bandwidths", DEFAULT_BANDWIDTH_WEIGHTS), rng
    )
    jitter_ratio = float(
        _resolve_value(network_raw.get("latency_jitter_ratio", 0.3), rng)
    )

    fuzzer_section: dict[str, Any] = {
        "run_index": run_index,
        "template_seed": template_seed,
        "seed": seed,
        "duration_secs": duration_secs,
        "output_dir": fuzzer_raw["output_dir"],
        "runner": runner,
        "base_genesis_dir": fuzzer_raw.get(
            "base_genesis_dir", "shadow-devnet/genesis"
        ),
    }

    simulation_section: dict[str, Any] = {
        "total_nodes": total_nodes,
        "total_subnets": total_subnets,
        "aggregators_per_subnet": aggregators_per_subnet,
        "signatures_aggregation_rate": sig_agg_rate,
        "recursive_aggregation_rate": rec_agg_rate,
    }

    resolved: dict[str, Any] = {
        "fuzzer": fuzzer_section,
        "simulation": simulation_section,
        "clients": {k: round(v, 4) for k, v in client_weights.items()},
        "node_counts": node_counts,
    }

    resolved["_internal"] = {
        "client_list": client_list,
        "region_weights": region_weights,
        "bandwidth_weights": bandwidth_weights,
        "jitter_ratio": jitter_ratio,
        "rng_state": rng,
    }

    return resolved


def _validate_template(template: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    fz = template.get("fuzzer", {})
    if not isinstance(fz, dict):
        errors.append("[fuzzer] section missing or not a table")
        return errors

    runner = fz.get("runner", "local")
    if runner not in ("local", "docker-arm"):
        errors.append(f"runner must be 'local' or 'docker-arm', got '{runner}'")

    clients = template.get("clients", {})
    if not clients:
        errors.append("[clients] section missing or empty")

    SCRIPT_DIR = REPO_ROOT
    for client_name in clients:
        cmd = SCRIPT_DIR / "client-cmds" / f"{client_name}-cmd.sh"
        if not cmd.is_file():
            errors.append(
                f"client '{client_name}' has no client-cmds/{client_name}-cmd.sh"
            )

    return errors


def _run_genesis(run_dir: Path, base_genesis_dir: str) -> None:
    run_dir = run_dir.resolve()
    script = REPO_ROOT / "generate-genesis.sh"
    genesis_dir = run_dir / "genesis"
    subprocess.run(
        [
            str(script),
            str(genesis_dir),
            "--genesis-time",
            str(SHADOW_GENESIS_TIME),
            "--forceKeyGen",
        ],
        check=True,
    )


def _run_topology(run_dir: Path, resolved: dict[str, Any]) -> None:
    run_dir = run_dir.resolve()
    internal = resolved["_internal"]
    region_weights = internal["region_weights"]
    bandwidth_weights = internal["bandwidth_weights"]
    jitter_ratio = internal["jitter_ratio"]
    seed = resolved["fuzzer"]["seed"]
    total_nodes = resolved["simulation"]["total_nodes"]

    script = FUZZER_ROOT / "generate-shadow-topology.py"
    cmd: list[str] = [
        sys.executable,
        str(script),
        str(total_nodes),
        str(run_dir),
        "--seed",
        str(seed),
        "--jitter",
        str(jitter_ratio),
        "--region-weights",
        json.dumps(region_weights),
        "--bandwidth-weights",
        json.dumps(bandwidth_weights),
    ]
    subprocess.run(cmd, check=True)


def _run_shadow_yaml(run_dir: Path, resolved: dict[str, Any]) -> None:
    run_dir = run_dir.resolve()
    script = REPO_ROOT / "generate-shadow-yaml.sh"
    genesis_dir = run_dir / "genesis"
    seed = resolved["fuzzer"]["seed"]
    duration = resolved["fuzzer"]["duration_secs"]
    stop_time = f"{duration}s"
    shadow_yaml = run_dir / "shadow.yaml"
    topology_gml = run_dir / "topology.gml"
    bandwidths_json = run_dir / "bandwidths.json"

    cmd: list[str] = [
        "bash",
        str(script),
        str(genesis_dir),
        "--project-root",
        str(REPO_ROOT.parent),
        "--stop-time",
        stop_time,
        "--output",
        str(shadow_yaml),
        "--seed",
        str(seed),
        "--shadow-data-dir",
        str(run_dir / "shadow.data"),
    ]

    if topology_gml.is_file() and bandwidths_json.is_file():
        cmd += [
            "--topology-gml",
            str(topology_gml),
            "--bandwidths-json",
            str(bandwidths_json),
        ]

    subprocess.run(cmd, check=True)


def _run_shadow(run_dir: Path, resolved: dict[str, Any], dry_run: bool = False) -> None:
    run_dir = run_dir.resolve()
    shadow_yaml = run_dir / "shadow.yaml"
    shadow_data = run_dir / "shadow.data"
    runner = resolved["fuzzer"]["runner"]

    if shadow_data.exists():
        shutil.rmtree(shadow_data)

    if dry_run:
        print(f"  [dry-run] Would clean {shadow_data}")
        print(f"  [dry-run] Would run: shadow {shadow_yaml}")
        return

    if runner == "local":
        subprocess.run(
            ["shadow", "-d", str(shadow_data), str(shadow_yaml)],
            check=True,
        )
    elif runner == "docker-arm":
        project_root = REPO_ROOT.parent.resolve()
        subprocess.run(
            [
                "docker", "run", "--rm",
                "--name", "shadow-sim-container",
                "--platform", "linux/arm64",
                "--security-opt", "seccomp=unconfined",
                "--shm-size", "4g",
                "-v", f"{project_root}:{project_root}",
                "-v", f"{run_dir}:{run_dir}",
                "-w", str(project_root),
                "--entrypoint", "/bin/bash",
                "kamilsa/shadow-arm:latest",
                "-c", f"shadow -d {shadow_data} {shadow_yaml}",
            ],
            check=True,
        )


def _run_stats(run_dir: Path, metadata_path: Path) -> None:
    run_dir = run_dir.resolve()
    script = FUZZER_ROOT / "stats-shadow.py"
    subprocess.run(
        [sys.executable, str(script), str(run_dir), "--metadata-json", str(metadata_path)],
        check=True,
    )


def _generate_run_id(run_index: int) -> str:
    try:
        import coolname

        return coolname.generate_slug(3)
    except ImportError:
        return f"run-{run_index:04d}"


def _validate_resolved(resolved: dict[str, Any]) -> list[str]:
    warnings: list[str] = []
    sim = resolved["simulation"]
    total_nodes = sim["total_nodes"]
    total_subnets = sim["total_subnets"]
    agg_per_subnet = sim["aggregators_per_subnet"]

    if total_subnets > total_nodes:
        warnings.append(
            f"total_subnets ({total_subnets}) > total_nodes ({total_nodes}); "
            "some subnets may have no nodes"
        )

    node_counts = resolved.get("node_counts", {})
    for subnet in range(total_subnets):
        nodes_in_subnet = sum(
            1
            for i in range(total_nodes)
            if i % total_subnets == subnet
        )
        if nodes_in_subnet < agg_per_subnet:
            warnings.append(
                f"subnet {subnet}: only {nodes_in_subnet} nodes available, "
                f"requested {agg_per_subnet} aggregators"
            )

    sampled_client_count = sum(node_counts.values())
    if sampled_client_count != total_nodes:
        warnings.append(
            f"sampled client count ({sampled_client_count}) != total_nodes ({total_nodes})"
        )

    return warnings


def main() -> None:
    dry_run = "--dry-run" in sys.argv
    args = [a for a in sys.argv[1:] if a != "--dry-run"]
    config_path = args[0] if args else "config.example.toml"
    config_path_abs = Path(config_path)
    if not config_path_abs.is_absolute():
        config_path_abs = Path.cwd() / config_path

    if not config_path_abs.is_file():
        print(f"ERROR: config file not found: {config_path_abs}", file=sys.stderr)
        sys.exit(1)

    with open(config_path_abs, "rb") as f:
        template = tomllib.load(f)

    errors = _validate_template(template)
    if errors:
        for e in errors:
            print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

    fuzzer = template["fuzzer"]
    max_runs = _resolve_value(fuzzer["max_runs"], random.Random(0))
    if dry_run:
        max_runs = 1
    output_dir = Path(fuzzer.get("output_dir", "fuzzer-output"))
    if not output_dir.is_absolute():
        output_dir = config_path_abs.parent / output_dir
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Fuzzer: max_runs={max_runs}, output_dir={output_dir}")
    print(f"Config: {config_path_abs}")
    print()

    for run_index in range(int(max_runs)):
        print(f"--- Run {run_index + 1}/{max_runs} ---")

        resolved = _resolve_config(template, run_index)
        warnings = _validate_resolved(resolved)
        for w in warnings:
            print(f"  WARNING: {w}")

        run_id = _generate_run_id(run_index)
        run_dir = output_dir / run_id
        while run_dir.exists():
            run_id = _generate_run_id(run_index + 1000)
            run_dir = output_dir / run_id
        run_dir.mkdir(parents=True, exist_ok=False)

        print(f"  Run ID: {run_id}")
        print(f"  Seed: {resolved['fuzzer']['seed']}")
        print(f"  Nodes: {resolved['simulation']['total_nodes']}")
        print(f"  Subnets: {resolved['simulation']['total_subnets']}")
        print(f"  Duration: {resolved['fuzzer']['duration_secs']}s")
        print(f"  Node counts: {resolved['node_counts']}")

        internal = resolved.pop("_internal", {})

        print("  Generating validator config...")
        _write_validator_config(
            run_dir,
            internal["client_list"],
            resolved["simulation"]["total_subnets"],
            resolved["simulation"]["aggregators_per_subnet"],
            internal["rng_state"],
        )

        print("  Writing run metadata...")
        metadata = {
            "run_id": run_id,
            "run_index": run_index,
            "fuzzer": resolved["fuzzer"],
            "simulation": resolved["simulation"],
            "clients": resolved.get("clients", {}),
            "node_counts": resolved.get("node_counts", {}),
        }
        metadata_path = run_dir / "run-metadata.json"
        metadata_path.write_text(json.dumps(metadata, indent=2))
        print(f"  Wrote {metadata_path}")

        generate_genesis = not dry_run

        if generate_genesis:
            print("  Generating genesis...")
            _run_genesis(run_dir, str(fuzzer.get("base_genesis_dir", "shadow-devnet/genesis")))

        print("  Generating topology...")
        _run_topology(run_dir, {**resolved, "_internal": internal})

        if generate_genesis:
            print("  Generating shadow.yaml...")
            _run_shadow_yaml(run_dir, {**resolved, "_internal": internal})

        print("  Running Shadow...")
        _run_shadow(run_dir, {**resolved, "_internal": internal}, dry_run=dry_run)

        if not dry_run:
            print("  Collecting stats...")
            _run_stats(run_dir, metadata_path)
        else:
            print("  [dry-run] Writing metadata-only stats.json")
            dry_stats = {
                "blocks": {"slots": [], "summary": {"warning": "dry-run: no simulation data"}},
                "attestations": {"slots": [], "summary": {"warning": "dry-run: no simulation data"}},
                "node_distribution": {
                    "clients": metadata["node_counts"],
                    "regions": {},
                    "bandwidths": {},
                },
                "warnings": ["dry-run"],
            }
            dry_stats.update(metadata)
            (run_dir / "stats.json").write_text(json.dumps(dry_stats, indent=2))
            print(f"  Wrote {run_dir / 'stats.json'}")

        print(f"  Done → {run_dir}")
        print()

    print(f"All {max_runs} runs complete.")


if __name__ == "__main__":
    main()
