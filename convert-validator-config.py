#!/usr/bin/env python3
"""
Convert validator-config.yaml to upstreams.json for leanpoint,
or emit Nemo LEAN_API_URL / env file.

This script reads a validator-config.yaml file (used by lean-quickstart)
and generates an upstreams.json file that leanpoint can use to monitor
multiple lean nodes. It can also build the comma-separated LEAN_API_URL
that Nemo expects (one base URL per validator, apiPort/httpPort).

Usage:
    python3 convert-validator-config.py [validator-config.yaml] [output.json] [--docker]

    python3 convert-validator-config.py --print-lean-api-url [validator-config.yaml] [--docker]

    python3 convert-validator-config.py --write-nemo-env <output.env> <validator-config.yaml> [--docker]

Options:
    --docker  Use host.docker.internal so a container on the host can reach
              validators on the host (local devnet + Docker).
    --all-upstreams  Emit one upstream per validator (default; kept for compatibility).
    --subnet-sample  Legacy: at most N validators per attestation subnet (see
              LEANPOINT_UPSTREAMS_PER_SUBNET, default 2). Not used unless this flag
              is set.

Examples:
    python3 convert-validator-config.py \\
        local-devnet/genesis/validator-config.yaml \\
        upstreams.json

    python3 convert-validator-config.py \\
        ansible-devnet/genesis/validator-config.yaml \\
        upstreams.json

    python3 convert-validator-config.py \\
        local-devnet/genesis/validator-config.yaml \\
        upstreams-local-docker.json --docker
"""

import os
import sys
import json
import yaml
from collections import defaultdict
from typing import Any, Optional


def _attestation_committee_count(config: dict) -> Optional[int]:
    """Subnet count from config.config.attestation_committee_count, or None if unset/invalid."""
    cfg = config.get("config")
    if not isinstance(cfg, dict):
        return None
    raw = cfg.get("attestation_committee_count")
    if raw is None:
        return None
    try:
        n = int(raw)
    except (TypeError, ValueError):
        return None
    if n < 1:
        return None
    return n


def _select_validators_for_leanpoint(
    validators: list[dict[str, Any]],
    subnet_count: Optional[int],
    *,
    per_subnet: int,
    all_upstreams: bool,
) -> list[tuple[int, dict[str, Any]]]:
    """
    Return (global_index, validator) rows to expose as leanpoint upstreams.

    When subnet_count is set and all_upstreams is False, keep at most `per_subnet`
    validators per attestation subnet (index % subnet_count). Each subnet includes
    the first validator with isAggregator: true in YAML order when present, then
    fills remaining slots with the next validators in that subnet not yet chosen.
    """
    if all_upstreams or subnet_count is None:
        return list(enumerate(validators))

    by_subnet: dict[int, list[tuple[int, dict[str, Any]]]] = defaultdict(list)
    for i, v in enumerate(validators):
        by_subnet[i % subnet_count].append((i, v))

    selected: list[tuple[int, dict[str, Any]]] = []
    for s in sorted(by_subnet.keys()):
        group = by_subnet[s]
        chosen: list[tuple[int, dict[str, Any]]] = []
        chosen_idx: set[int] = set()

        for idx, val in group:
            if val.get("isAggregator") is True:
                chosen.append((idx, val))
                chosen_idx.add(idx)
                break
        else:
            if group:
                idx, val = group[0]
                chosen.append((idx, val))
                chosen_idx.add(idx)

        for idx, val in group:
            if len(chosen) >= per_subnet:
                break
            if idx in chosen_idx:
                continue
            chosen.append((idx, val))
            chosen_idx.add(idx)

        selected.extend(chosen)

    return selected


def convert_validator_config(
    yaml_path: str,
    output_path: str,
    base_port: int = 8081,
    docker_host: bool = False,
    *,
    all_upstreams: bool = True,
    subnet_sample: bool = False,
    per_subnet: Optional[int] = None,
):
    """
    Convert validator-config.yaml to upstreams.json.

    Args:
        yaml_path: Path to validator-config.yaml
        output_path: Path to output upstreams.json
        base_port: Base HTTP port for beacon API (default: 8081)
        docker_host: If True, use host.docker.internal so leanpoint in Docker
            can reach a devnet running on the host (Docker Desktop/Orbstack).
        all_upstreams: If True (default), emit one upstream per validator.
        subnet_sample: If True, keep at most per_subnet validators per attestation
            subnet instead of the full list.
        per_subnet: Max upstreams per attestation subnet when subnet_sample is True;
            default from LEANPOINT_UPSTREAMS_PER_SUBNET env or 2.
    """
    with open(yaml_path, 'r') as f:
        config = yaml.safe_load(f)

    if 'validators' not in config:
        print("Error: No 'validators' key found in config", file=sys.stderr)
        sys.exit(1)

    validators = config["validators"]
    committee = _attestation_committee_count(config)

    use_subnet_sample = subnet_sample and not all_upstreams
    if use_subnet_sample:
        if per_subnet is None:
            try:
                per_subnet = int(os.environ.get("LEANPOINT_UPSTREAMS_PER_SUBNET", "2"))
            except ValueError:
                per_subnet = 2
        if per_subnet < 1:
            per_subnet = 1
        rows = _select_validators_for_leanpoint(
            validators,
            committee,
            per_subnet=per_subnet,
            all_upstreams=False,
        )
        if committee is not None:
            print(
                f"Info: Leanpoint upstream subset (--subnet-sample): "
                f"attestation_committee_count={committee}, up to {per_subnet} "
                f"validator(s) per subnet ({len(rows)} upstreams from "
                f"{len(validators)} validators).",
                file=sys.stderr,
            )
    else:
        rows = list(enumerate(validators))

    upstreams = []

    for idx, validator in rows:
        name = validator.get('name', f'validator_{idx}')

        # Try to get IP from enrFields, default to localhost
        ip = "127.0.0.1"
        enr = validator.get('enrFields')
        if isinstance(enr, dict) and enr.get('ip') is not None:
            ip = enr['ip']
        if docker_host:
            ip = "host.docker.internal"

        # Use apiPort, falling back to httpPort (used by Lantern), then a derived default.
        http_port = validator.get('apiPort') or validator.get('httpPort') or (base_port + idx)

        upstream = {
            "name": name,
            "url": f"http://{ip}:{http_port}",
            "path": "/v0/health"  # Health check endpoint
        }

        upstreams.append(upstream)

    output = {"upstreams": upstreams}

    with open(output_path, 'w') as f:
        json.dump(output, f, indent=2)

    print(f"✅ Wrote {len(upstreams)} leanpoint upstream(s) to {output_path}")
    print(f"\nGenerated upstreams:")
    for u in upstreams:
        print(f"  - {u['name']}: {u['url']}{u['path']}")

    print(f"\n💡 To use: leanpoint --upstreams-config {output_path}")


def nemo_lean_api_url_string(
    yaml_path: str,
    base_port: int = 8081,
    docker_host: bool = False,
) -> str:
    """
    Comma-separated Lean HTTP API base URLs for Nemo (no path), one per validator.

    Skips validators with empty enrFields.ip when not using docker_host (e.g. placeholder ansible rows).
    """
    with open(yaml_path, 'r') as f:
        config = yaml.safe_load(f)

    if 'validators' not in config:
        raise ValueError("No 'validators' key found in config")

    bases: list[str] = []
    for idx, validator in enumerate(config['validators']):
        name = validator.get('name', f'validator_{idx}')
        ip = "127.0.0.1"
        enr = validator.get('enrFields')
        if isinstance(enr, dict) and enr.get('ip') is not None:
            ip = enr['ip']
        if docker_host:
            ip = "host.docker.internal"
        elif isinstance(ip, str) and not ip.strip():
            print(
                f"Warning: skipping validator '{name}' for Nemo LEAN_API_URL: empty enrFields.ip",
                file=sys.stderr,
            )
            continue

        http_port = validator.get('apiPort') or validator.get('httpPort') or (base_port + idx)
        bases.append(f"http://{ip}:{http_port}")

    if not bases:
        raise ValueError(
            "No validators with a usable IP for Nemo; assign enrFields.ip or use --docker for local."
        )
    return ",".join(bases)


def write_nemo_env_file(
    yaml_path: str,
    env_out_path: str,
    base_port: int = 8081,
    docker_host: bool = False,
) -> None:
    """Write a docker --env-file compatible file for Nemo (LEAN_API_URL + defaults)."""
    url_string = nemo_lean_api_url_string(yaml_path, base_port=base_port, docker_host=docker_host)
    if any(c in url_string for c in (' ', '"', '\n', '\\')):
        escaped = url_string.replace("\\", "\\\\").replace('"', '\\"')
        line = f'LEAN_API_URL="{escaped}"\n'
    else:
        line = f"LEAN_API_URL={url_string}\n"
    with open(env_out_path, "w") as f:
        f.write(line)
        f.write("NEMO_PORT=5053\n")
        f.write("NEMO_DB_PATH=/data/nemo.db\n")
        f.write("SYNC_INTERVAL_SEC=4\n")


def main():
    docker_host = "--docker" in sys.argv
    subnet_sample = "--subnet-sample" in sys.argv
    # Default: every validator is an upstream. --all-upstreams is a no-op (compat).
    all_upstreams = "--subnet-sample" not in sys.argv
    argv = [
        a
        for a in sys.argv[1:]
        if a not in ("--docker", "--all-upstreams", "--subnet-sample")
    ]

    if "--print-lean-api-url" in argv:
        argv = [a for a in argv if a != "--print-lean-api-url"]
        yaml_path = argv[0] if argv else "local-devnet/genesis/validator-config.yaml"
        try:
            print(nemo_lean_api_url_string(yaml_path, docker_host=docker_host))
        except (OSError, ValueError, yaml.YAMLError) as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)
        return

    if "--write-nemo-env" in argv:
        i = argv.index("--write-nemo-env")
        try:
            env_out = argv[i + 1]
            yaml_path = argv[i + 2]
        except IndexError:
            print(
                "Usage: convert-validator-config.py --write-nemo-env <output.env> "
                "<validator-config.yaml> [--docker]",
                file=sys.stderr,
            )
            sys.exit(1)
        # Remove consumed args so stray args don't confuse
        rest = argv[:i] + argv[i + 3:]
        if rest:
            print(f"Warning: ignoring extra arguments: {rest}", file=sys.stderr)
        try:
            write_nemo_env_file(yaml_path, env_out, docker_host=docker_host)
            print(f"✅ Wrote Nemo env file to {env_out}")
        except (OSError, ValueError, yaml.YAMLError) as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)
        return

    args = argv
    if len(args) < 2:
        if len(args) == 0:
            print(__doc__)
            print("\nUsing default paths...")
            yaml_path = "local-devnet/genesis/validator-config.yaml"
            output_path = "upstreams.json"
        else:
            yaml_path = args[0]
            output_path = "upstreams-local-docker.json" if docker_host else "upstreams.json"
    else:
        yaml_path = args[0]
        output_path = args[1]

    try:
        convert_validator_config(
            yaml_path,
            output_path,
            docker_host=docker_host,
            all_upstreams=all_upstreams,
            subnet_sample=subnet_sample,
        )
    except FileNotFoundError as e:
        print(f"Error: File not found: {e}", file=sys.stderr)
        sys.exit(1)
    except yaml.YAMLError as e:
        print(f"Error: Invalid YAML: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
