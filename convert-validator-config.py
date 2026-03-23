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

import sys
import json
import yaml


def convert_validator_config(
    yaml_path: str,
    output_path: str,
    base_port: int = 8081,
    docker_host: bool = False,
):
    """
    Convert validator-config.yaml to upstreams.json.

    Args:
        yaml_path: Path to validator-config.yaml
        output_path: Path to output upstreams.json
        base_port: Base HTTP port for beacon API (default: 8081)
        docker_host: If True, use host.docker.internal so leanpoint in Docker
            can reach a devnet running on the host (Docker Desktop/Orbstack).
    """
    with open(yaml_path, 'r') as f:
        config = yaml.safe_load(f)

    if 'validators' not in config:
        print("Error: No 'validators' key found in config", file=sys.stderr)
        sys.exit(1)

    upstreams = []

    for idx, validator in enumerate(config['validators']):
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

    print(f"✅ Converted {len(upstreams)} validators to {output_path}")
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
    argv = [a for a in sys.argv[1:] if a != "--docker"]
    docker_host = "--docker" in sys.argv

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
        convert_validator_config(yaml_path, output_path, docker_host=docker_host)
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
