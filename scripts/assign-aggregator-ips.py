#!/usr/bin/env python3
"""
Assign dedicated aggregator-server IPs after aggregator selection (spin-node.sh).

Each attestation subnet's aggregator (validator_index % committee_count) is placed
on the matching IP from lean_ethereum_servers.txt Aggregator_servers (one container
per IP: quic 9001, api 5055, metrics 9102). Non-aggregators are evicted from those
IPs to validator-server hosts with free port slots.
"""

from __future__ import annotations

import argparse
import sys
from collections import defaultdict
from typing import Any

import yaml

# Subnet index → Aggregator_servers IP (lean_ethereum_servers.txt lines 45–52).
SUBNET_AGGREGATOR_IPS: tuple[str, ...] = (
    "77.42.121.211",  # subnet 0
    "89.167.41.98",  # subnet 1
    "89.167.114.168",  # subnet 2
    "89.167.120.1",  # subnet 3
    "89.167.112.241",  # subnet 4
    "95.217.153.36",  # subnet 5
    "89.167.3.22",  # subnet 6
    "89.167.120.224",  # subnet 7
)

AGGREGATOR_IP_SET = frozenset(SUBNET_AGGREGATOR_IPS)
AGGREGATOR_QUIC = 9001
AGGREGATOR_METRICS = 9102
AGGREGATOR_API = 5055


def _committee_count(config: dict[str, Any]) -> int:
    cfg = config.get("config") or {}
    raw = cfg.get("attestation_committee_count", 1)
    try:
        n = int(raw)
    except (TypeError, ValueError):
        n = 1
    return max(1, n)


def _rows_with_subnet(validators: list[dict[str, Any]], committee_count: int) -> list[tuple[dict[str, Any], int, int]]:
    """(validator, validator_index, subnet) for each YAML row."""
    out: list[tuple[dict[str, Any], int, int]] = []
    vi = 0
    for v in validators:
        count = int(v.get("count") or 1)
        if "subnet" in v and v["subnet"] is not None and v["subnet"] != "":
            subnet = int(v["subnet"])
        else:
            subnet = vi % committee_count
        out.append((v, vi, subnet))
        vi += count
    return out


def _ports_for_quic(quic: int) -> tuple[int, int]:
    offset = quic - AGGREGATOR_QUIC
    return AGGREGATOR_METRICS + offset, AGGREGATOR_API + offset


def _set_ports(v: dict[str, Any], quic: int) -> None:
    v.setdefault("enrFields", {})["quic"] = quic
    metrics, api = _ports_for_quic(quic)
    v["metricsPort"] = metrics
    if "apiPort" in v or "httpPort" not in v:
        v["apiPort"] = api


def _used_quic_on_ip(validators: list[dict[str, Any]], ip: str) -> set[int]:
    used: set[int] = set()
    for v in validators:
        if v.get("enrFields", {}).get("ip") == ip:
            used.add(int(v["enrFields"].get("quic", AGGREGATOR_QUIC)))
    return used


def _find_validator_slot(validators: list[dict[str, Any]], exclude_ips: frozenset[str]) -> tuple[str, int]:
    """Next free (ip, quic) on a non-aggregator host (up to 4 slots per IP)."""
    by_ip: dict[str, set[int]] = defaultdict(set)
    for v in validators:
        ip = v.get("enrFields", {}).get("ip", "")
        if not ip or ip in exclude_ips:
            continue
        by_ip[ip].add(int(v.get("enrFields", {}).get("quic", AGGREGATOR_QUIC)))

    for ip in sorted(by_ip.keys()):
        for quic in range(AGGREGATOR_QUIC, AGGREGATOR_QUIC + 4):
            if quic not in by_ip[ip]:
                return ip, quic

  # No existing validator IP has room — pick any non-aggregator IP (should not happen on devnet).
    for ip in sorted(by_ip.keys()):
        return ip, AGGREGATOR_QUIC
    raise RuntimeError("no validator-server IP with a free port slot for eviction")


def assign_aggregator_ips(config: dict[str, Any], *, dry_run: bool = False) -> list[str]:
    validators: list[dict[str, Any]] = config.get("validators") or []
    if not validators:
        return []

    committee_count = _committee_count(config)
    if committee_count > len(SUBNET_AGGREGATOR_IPS):
        raise ValueError(
            f"attestation_committee_count={committee_count} exceeds "
            f"{len(SUBNET_AGGREGATOR_IPS)} aggregator server IPs"
        )

    rows = _rows_with_subnet(validators, committee_count)
    aggregators_by_subnet: dict[int, dict[str, Any]] = {}
    for v, _vi, subnet in rows:
        if v.get("isAggregator") is True:
            if subnet in aggregators_by_subnet:
                raise ValueError(
                    f"subnet {subnet}: multiple aggregators "
                    f"({aggregators_by_subnet[subnet]['name']}, {v['name']})"
                )
            aggregators_by_subnet[subnet] = v

    for subnet in range(committee_count):
        if subnet not in aggregators_by_subnet:
            raise ValueError(f"subnet {subnet}: no aggregator (isAggregator: true)")

    # ip -> aggregator name that must own this host
    owner_by_agg_ip: dict[str, str] = {}
    for subnet, agg in aggregators_by_subnet.items():
        target_ip = SUBNET_AGGREGATOR_IPS[subnet]
        owner_by_agg_ip[target_ip] = agg["name"]

    changes: list[str] = []

    def log(msg: str) -> None:
        changes.append(msg)

    # Evict validators that occupy an aggregator IP but are not the designated owner.
    for v in validators:
        ip = v.get("enrFields", {}).get("ip", "")
        if ip not in AGGREGATOR_IP_SET:
            continue
        owner = owner_by_agg_ip.get(ip)
        if owner == v["name"]:
            continue
        new_ip, new_quic = _find_validator_slot(validators, AGGREGATOR_IP_SET)
        log(f"evict {v['name']}: {ip} -> {new_ip} quic {new_quic}")
        if not dry_run:
            v["enrFields"]["ip"] = new_ip
            _set_ports(v, new_quic)

    # Place each subnet aggregator on its dedicated IP (single slot).
    for subnet, agg in sorted(aggregators_by_subnet.items()):
        target_ip = SUBNET_AGGREGATOR_IPS[subnet]
        old_ip = agg.get("enrFields", {}).get("ip", "")
        if old_ip != target_ip or int(agg.get("enrFields", {}).get("quic", 0)) != AGGREGATOR_QUIC:
            log(
                f"aggregator {agg['name']} (subnet {subnet}): "
                f"{old_ip} -> {target_ip} quic {AGGREGATOR_QUIC}"
            )
        if not dry_run:
            agg.setdefault("enrFields", {})["ip"] = target_ip
            _set_ports(agg, AGGREGATOR_QUIC)

    # Verify: exactly one validator per aggregator IP and all aggregators use allowed IPs.
    if not dry_run:
        on_agg_ip: dict[str, list[str]] = defaultdict(list)
        for v in validators:
            ip = v.get("enrFields", {}).get("ip", "")
            if ip in AGGREGATOR_IP_SET:
                on_agg_ip[ip].append(v["name"])
        for ip, names in on_agg_ip.items():
            if len(names) != 1:
                raise RuntimeError(f"aggregator IP {ip}: expected 1 container, got {names}")
        for subnet, agg in aggregators_by_subnet.items():
            ip = agg["enrFields"]["ip"]
            expected = SUBNET_AGGREGATOR_IPS[subnet]
            if ip != expected:
                raise RuntimeError(f"{agg['name']}: expected IP {expected}, got {ip}")
            if ip not in AGGREGATOR_IP_SET:
                raise RuntimeError(f"{agg['name']}: IP {ip} is not an aggregator server")

    return changes


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("validator_config", help="Path to validator-config.yaml")
    parser.add_argument("--dry-run", action="store_true", help="Print changes without writing")
    args = parser.parse_args()

    with open(args.validator_config) as fh:
        config = yaml.safe_load(fh)

    try:
        changes = assign_aggregator_ips(config, dry_run=args.dry_run)
    except (ValueError, RuntimeError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)

    if not changes:
        print("Aggregator IPs already aligned with aggregator servers.")
        return

    for line in changes:
        print(line)

    if args.dry_run:
        print("(dry-run: no file written)")
        return

    with open(args.validator_config, "w") as fh:
        yaml.dump(config, fh, default_flow_style=False, sort_keys=False)
    print(f"Updated {args.validator_config}")


if __name__ == "__main__":
    main()
