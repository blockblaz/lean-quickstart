#!/usr/bin/env python3
"""
Generate an expanded validator-config.yaml from a template by distributing
each client across N subnets, one node per subnet per server.

Subnet assignment rules
-----------------------
  - Each server (IP) contributes exactly ONE node to each subnet.
  - No two nodes on the same server share a subnet.
  - Every subnet contains exactly the same number of clients.
  - Every subnet contains at least one unique client (i.e. no two subnets
    share a node identity).

These rules are automatically satisfied by the expansion algorithm: the
template is expected to have one entry per client, each on its own server.
The script validates this assumption and errors out if it is violated.

Port assignment
---------------
  For subnet i, all ports are incremented by i relative to the template entry:
    quicPort    += i
    metricsPort += i
    apiPort     += i   (or httpPort for Lantern)

  This keeps nodes on the same host from binding conflicting ports.

Limits
------
  N must be between 1 and 5 (inclusive).
  N=1 produces a single subnet (nodes renamed to {client}_0) with no port changes.

Usage
-----
    python3 generate-subnet-config.py <template.yaml> <N> <output.yaml>

Example
-------
    python3 generate-subnet-config.py \\
        ansible-devnet/genesis/validator-config.yaml 2 \\
        ansible-devnet/genesis/validator-config-subnets-2.yaml
"""

from __future__ import annotations

import copy
import secrets
import sys
from collections import Counter

import yaml

MAX_SUBNETS = 5


def _client_name(node_name: str) -> str:
    """Extract the client type prefix (e.g. 'zeam' from 'zeam_0')."""
    return node_name.split("_")[0]


def _validate_template(validators: list[dict]) -> None:
    """
    Enforce that the template satisfies the one-server-one-node requirement:
      - No two entries share the same IP address.
      - No two entries share the same client type (name prefix).
    Either violation would break the subnet isolation guarantee.
    """
    ips     = [v["enrFields"]["ip"] for v in validators]
    clients = [_client_name(v["name"]) for v in validators]

    duplicate_ips = [ip for ip, n in Counter(ips).items() if n > 1]
    if duplicate_ips:
        raise ValueError(
            "Template validator-config.yaml has multiple entries sharing the "
            f"same IP address: {duplicate_ips}. Each server must have exactly "
            "one entry in the template. Use --subnets to add more nodes per server."
        )

    duplicate_clients = [c for c, n in Counter(clients).items() if n > 1]
    if duplicate_clients:
        raise ValueError(
            "Template validator-config.yaml has multiple entries for the same "
            f"client type: {duplicate_clients}. Each client type must appear "
            "exactly once in the template."
        )


def expand(template: dict, n_subnets: int) -> dict:
    """
    Return a new config dict with every validator entry replicated across
    n_subnets subnets.

    Output ordering: all subnet-0 nodes first, then all subnet-1 nodes, …
    This makes the subnet grouping visually obvious in the generated file.
    """
    validators = template["validators"]
    _validate_template(validators)

    result = copy.deepcopy(template)

    # attestation_committee_count must equal the number of subnets so that
    # each client correctly partitions itself into N separate committees.
    if "config" not in result:
        result["config"] = {}
    result["config"]["attestation_committee_count"] = n_subnets

    expanded: list[dict] = []

    for i in range(n_subnets):
        for validator in validators:
            client = _client_name(validator["name"])
            entry  = copy.deepcopy(validator)

            # Canonical name: {client}_{subnet_index}
            entry["name"]   = f"{client}_{i}"
            entry["subnet"] = i  # explicit membership for human readability

            # Every node beyond subnet 0 gets a fresh P2P identity key so
            # nodes on the same server have different identities.
            if i > 0:
                entry["privkey"] = secrets.token_hex(32)

            # Increment all network ports by the subnet index so nodes that
            # share a host do not bind the same port.
            entry["enrFields"]["quic"] = validator["enrFields"]["quic"] + i
            entry["metricsPort"]       = validator["metricsPort"] + i
            if "apiPort" in entry:
                entry["apiPort"]  = validator["apiPort"] + i
            if "httpPort" in entry:
                entry["httpPort"] = validator["httpPort"] + i

            # spin-node.sh re-assigns the aggregator before deploying.
            entry["isAggregator"] = False

            expanded.append(entry)

    result["validators"] = expanded
    return result


def main() -> None:
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <template.yaml> <N> <output.yaml>")
        sys.exit(1)

    template_path = sys.argv[1]
    output_path   = sys.argv[3]

    try:
        n_subnets = int(sys.argv[2])
        if not (1 <= n_subnets <= MAX_SUBNETS):
            raise ValueError
    except ValueError:
        print(
            f"Error: N must be an integer between 1 and {MAX_SUBNETS}, "
            f"got: {sys.argv[2]!r}"
        )
        sys.exit(1)

    with open(template_path) as fh:
        template = yaml.safe_load(fh)

    if "validators" not in template or not template["validators"]:
        print(f"Error: no validators found in {template_path}")
        sys.exit(1)

    try:
        expanded = expand(template, n_subnets)
    except ValueError as exc:
        print(f"Error: {exc}")
        sys.exit(1)

    with open(output_path, "w") as fh:
        yaml.dump(expanded, fh, default_flow_style=False, sort_keys=False)

    n_clients = len(template["validators"])
    n_nodes   = len(expanded["validators"])
    print(
        f"Generated {output_path}:\n"
        f"  {n_clients} client(s) × {n_subnets} subnet(s) = {n_nodes} nodes\n"
        f"  config.attestation_committee_count = {n_subnets}\n"
        f"  Each server contributes exactly 1 node per subnet (no intra-server subnet sharing)"
    )


if __name__ == "__main__":
    main()
