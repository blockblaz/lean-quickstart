#!/usr/bin/env python3
"""
Convert validator-config.yaml to upstreams.json for leanpoint.

This script reads a validator-config.yaml file (used by lean-quickstart)
and generates an upstreams.json file that leanpoint can use to monitor
multiple lean nodes.

Usage:
    python3 convert-validator-config.py [validator-config.yaml] [output.json] [--docker]

Options:
    --docker  Use host.docker.internal so leanpoint running in Docker can
              reach a devnet on the host (e.g. upstreams-local-docker.json).

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
        if 'enrFields' in validator and 'ip' in validator['enrFields']:
            ip = validator['enrFields']['ip']
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


def main():
    args = [a for a in sys.argv[1:] if a != "--docker"]
    docker_host = "--docker" in sys.argv

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
