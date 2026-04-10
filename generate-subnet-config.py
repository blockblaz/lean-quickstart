#!/usr/bin/env python3
"""
Generate an expanded validator-config.yaml from a template.

Two modes (chosen automatically):

1) **Replicate mode** (default) — unique IP per template row, each client type once.
   Each row is cloned N times (subnets 0..N-1) on the same IP with port offsets.
   Same behavior as the original lean-quickstart subnet generator.

2) **Shared-host mode** — template has duplicate IPs (multiple rows, same server).
   No row cloning; each row is one running node. Subnet membership is taken from
   each row's ``subnet`` field, or inferred from a numeric name suffix ``client_K``.

   - **One client type per IP, many rows** (e.g. zeam_0..zeam_4 on 37.27.0.1):
     infer ``subnet`` from the suffix K in ``name`` unless ``subnet`` is set.
   - **Several client types on one IP** (zeam + ream + … on the same box, each
     in a different subnet): every row for that IP **must** set explicit
     ``subnet`` (name suffix is ambiguous when several clients use *_0).

Limits: N (subnets / committee count) must be between 1 and 5.

Usage
-----
    python3 generate-subnet-config.py <template.yaml> <N> <output.yaml>
"""

from __future__ import annotations

import copy
import re
import secrets
import sys
from collections import Counter, defaultdict

import yaml

MAX_SUBNETS = 5


def _client_name(node_name: str) -> str:
    """Extract the client type prefix (e.g. 'zeam' from 'zeam_0')."""
    return node_name.split("_")[0]


def _has_duplicate_ips(validators: list[dict]) -> bool:
    ips = [v["enrFields"]["ip"] for v in validators]
    return any(n > 1 for n in Counter(ips).values())


def _subnet_from_name(name: str) -> int:
    """Parse subnet index from trailing _<digits> in node name."""
    m = re.match(r"^.+_(\d+)$", name)
    if not m:
        raise ValueError(
            f"Node {name!r}: with shared-IP templates, use a numeric suffix "
            f"(e.g. zeam_0) or set explicit 'subnet:'"
        )
    return int(m.group(1))


def _effective_subnet(
    v: dict,
    *,
    ip: str,
    clients_on_ip: set[str],
) -> int:
    if "subnet" in v and v["subnet"] is not None and v["subnet"] != "":
        return int(v["subnet"])
    if len(clients_on_ip) > 1:
        raise ValueError(
            f"Node {v['name']!r} on {ip}: multiple client types share this IP; "
            f"set an explicit integer 'subnet' on each row (name suffix alone is not enough)."
        )
    return _subnet_from_name(v["name"])


def _validate_shared_host_template(validators: list[dict], n_subnets: int) -> None:
    """Validate duplicate-IP (shared-host) layout and assign effective subnets."""
    by_ip: dict[str, list[dict]] = defaultdict(list)
    for v in validators:
        by_ip[v["enrFields"]["ip"]].append(v)

    seen_ip_subnet: set[tuple[str, int]] = set()
    seen_ip_client_subnet: set[tuple[str, str, int]] = set()

    for ip, group in by_ip.items():
        clients_on_ip = {_client_name(v["name"]) for v in group}
        for v in group:
            client = _client_name(v["name"])
            try:
                sn = _effective_subnet(v, ip=ip, clients_on_ip=clients_on_ip)
            except ValueError:
                raise
            if sn < 0 or sn >= n_subnets:
                raise ValueError(
                    f"Node {v['name']!r}: subnet {sn} out of range for --subnets {n_subnets} "
                    f"(valid: 0..{n_subnets - 1})"
                )
            key = (ip, sn)
            if key in seen_ip_subnet:
                raise ValueError(
                    f"IP {ip}: two nodes use subnet {sn}; each subnet index must be "
                    f"unique per server (distinct ports / one node per subnet per host)."
                )
            seen_ip_subnet.add(key)

            k2 = (ip, client, sn)
            if k2 in seen_ip_client_subnet:
                raise ValueError(
                    f"IP {ip}: duplicate entry for client {client!r} in subnet {sn}."
                )
            seen_ip_client_subnet.add(k2)


def _expand_shared_host(template: dict, n_subnets: int) -> dict:
    """Pass-through layout: one template row per node; set subnet + committee count."""
    validators = template["validators"]
    _validate_shared_host_template(validators, n_subnets)

    by_ip: dict[str, list[dict]] = defaultdict(list)
    for v in validators:
        by_ip[v["enrFields"]["ip"]].append(v)

    result = copy.deepcopy(template)
    if "config" not in result:
        result["config"] = {}
    result["config"]["attestation_committee_count"] = n_subnets

    out_vals: list[dict] = []
    for v in validators:
        entry = copy.deepcopy(v)
        ip = entry["enrFields"]["ip"]
        clients_on_ip = {_client_name(x["name"]) for x in by_ip[ip]}
        sn = _effective_subnet(entry, ip=ip, clients_on_ip=clients_on_ip)
        entry["subnet"] = sn
        entry["isAggregator"] = False
        out_vals.append(entry)

    result["validators"] = out_vals
    return result


def _validate_replicate_template(validators: list[dict]) -> None:
    """
    Enforce one-server-one-row for replicate mode:
      - No two entries share the same IP address.
      - No two entries share the same client type (name prefix).
    """
    ips = [v["enrFields"]["ip"] for v in validators]
    clients = [_client_name(v["name"]) for v in validators]

    duplicate_ips = [ip for ip, n in Counter(ips).items() if n > 1]
    if duplicate_ips:
        raise ValueError(
            "Internal error: replicate template must have unique IPs "
            f"(duplicates: {duplicate_ips})"
        )

    duplicate_clients = [c for c, n in Counter(clients).items() if n > 1]
    if duplicate_clients:
        raise ValueError(
            "Template validator-config.yaml has multiple entries for the same "
            f"client type: {duplicate_clients}. Each client type must appear "
            "exactly once in the template when using unique IPs, or use a "
            "shared-IP layout (multiple rows per IP) instead."
        )


def expand_replicate(template: dict, n_subnets: int) -> dict:
    """
    Replicate mode: each template row becomes N nodes (subnets 0..N-1) on that IP.
    """
    validators = template["validators"]
    _validate_replicate_template(validators)

    result = copy.deepcopy(template)

    if "config" not in result:
        result["config"] = {}
    result["config"]["attestation_committee_count"] = n_subnets

    expanded: list[dict] = []

    for i in range(n_subnets):
        for validator in validators:
            client = _client_name(validator["name"])
            entry = copy.deepcopy(validator)

            entry["name"] = f"{client}_{i}"
            entry["subnet"] = i

            if i > 0:
                entry["privkey"] = secrets.token_hex(32)

            entry["enrFields"]["quic"] = validator["enrFields"]["quic"] + i
            entry["metricsPort"] = validator["metricsPort"] + i
            if "apiPort" in entry:
                entry["apiPort"] = validator["apiPort"] + i
            if "httpPort" in entry:
                entry["httpPort"] = validator["httpPort"] + i

            entry["isAggregator"] = False

            expanded.append(entry)

    result["validators"] = expanded
    return result


def expand(template: dict, n_subnets: int) -> dict:
    if _has_duplicate_ips(template["validators"]):
        return _expand_shared_host(template, n_subnets)
    return expand_replicate(template, n_subnets)


def main() -> None:
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <template.yaml> <N> <output.yaml>")
        sys.exit(1)

    template_path = sys.argv[1]
    output_path = sys.argv[3]

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

    n_in = len(template["validators"])
    n_out = len(expanded["validators"])
    mode = "shared-host" if _has_duplicate_ips(template["validators"]) else "replicate"
    print(
        f"Generated {output_path}:\n"
        f"  mode = {mode}\n"
        f"  template rows = {n_in}, output nodes = {n_out}\n"
        f"  config.attestation_committee_count = {n_subnets}"
    )
    if mode == "replicate":
        print(
            f"  (replicate) {n_in} client(s) × {n_subnets} subnet(s) = {n_out} nodes"
        )
    else:
        print(
            "  (shared-host) one output row per template row; subnets from "
            "'subnet' field or numeric name suffix"
        )


if __name__ == "__main__":
    main()
