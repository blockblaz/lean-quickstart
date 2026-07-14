#!/usr/bin/env python3
"""Monitor all 8 subnet aggregators: timely coverage, publish lag, real aggregation time."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import urllib.request
from dataclasses import dataclass, field
from typing import Any

try:
    import yaml
except ImportError:
    sys.stderr.write("pip install pyyaml\n")
    sys.exit(1)

SUBNET_IPS = (
    "77.42.121.211",   # 0
    "89.167.41.98",    # 1
    "89.167.114.168",  # 2
    "89.167.120.1",    # 3
    "89.167.112.241",  # 4
    "95.217.153.36",   # 5
    "89.167.3.22",     # 6
    "89.167.120.224",  # 7
)


@dataclass
class AggInfo:
    subnet: int
    name: str
    client: str
    ip: str
    metrics_port: int


@dataclass
class AggReport:
    info: AggInfo
    metrics_ok: bool = False
    worker_metric: str | None = None
    worker_count: int = 0
    worker_mean_s: float | None = None
    worker_p50_s: float | None = None
    build_mean_s: float | None = None
    build_count: int = 0
    compute_ffi_mean_s: float | None = None
    skip_in_flight: int = 0
    coalesced_total: int = 0
    publish_total: int = 0
    timely_combined: int | None = None
    late_combined: int | None = None
    combined_combined: int | None = None
    timely_by_subnet: dict[int, int] = field(default_factory=dict)
    late_by_subnet: dict[int, int] = field(default_factory=dict)
    combined_by_subnet: dict[int, int] = field(default_factory=dict)
    log_agg_starts: int = 0
    log_in_flight: int = 0
    log_coalesced: int = 0
    log_publishes: int = 0
    publish_lag_p50: int | None = None
    publish_lag_mean: float | None = None
    publish_lag_n: int = 0
    publish_on_time_pct: float | None = None  # lag <= 2 slots
    container_image: str = ""
    errors: list[str] = field(default_factory=list)


def load_aggregators(cfg_path: str) -> list[AggInfo]:
    with open(cfg_path) as f:
        cfg = yaml.safe_load(f)
    validators = cfg.get("validators", cfg)
    by_ip: dict[str, dict[str, Any]] = {}
    for v in validators:
        if not isinstance(v, dict) or not v.get("isAggregator"):
            continue
        ip = v["enrFields"]["ip"]
        by_ip[ip] = v

    out: list[AggInfo] = []
    for subnet, ip in enumerate(SUBNET_IPS):
        v = by_ip.get(ip)
        if not v:
            out.append(
                AggInfo(
                    subnet=subnet,
                    name=f"?(missing@{ip})",
                    client="?",
                    ip=ip,
                    metrics_port=9102,
                )
            )
            continue
        name = v["name"]
        out.append(
            AggInfo(
                subnet=subnet,
                name=name,
                client=name.split("_")[0],
                ip=ip,
                metrics_port=int(v.get("metricsPort", 9102)),
            )
        )
    return out


def fetch_metrics(ip: str, port: int, timeout: float = 8.0) -> str:
    url = f"http://{ip}:{port}/metrics"
    with urllib.request.urlopen(url, timeout=timeout) as resp:
        return resp.read().decode("utf-8", errors="replace")


def ssh_cmd(ssh_key: str, ip: str, remote: str, timeout: int = 20) -> str:
    cmd = [
        "ssh",
        "-i",
        ssh_key,
        "-o",
        "BatchMode=yes",
        "-o",
        "ConnectTimeout=8",
        "-o",
        "StrictHostKeyChecking=accept-new",
        f"root@{ip}",
        remote,
    ]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        if r.returncode != 0 and r.stderr.strip():
            return ""
        return r.stdout
    except (subprocess.TimeoutExpired, OSError):
        return ""


def hist_stats(text: str, prefix: str) -> tuple[int, float, float | None, float | None]:
    buckets: dict[str, float] = {}
    count = 0
    total = 0.0
    for line in text.splitlines():
        if line.startswith(prefix + "_bucket"):
            le = line.split('le="')[1].split('"')[0]
            buckets[le] = float(line.rsplit(" ", 1)[-1])
        elif line.startswith(prefix + "_count "):
            count = int(float(line.rsplit(" ", 1)[-1]))
        elif line.startswith(prefix + "_sum "):
            total = float(line.rsplit(" ", 1)[-1])

    if count == 0:
        return 0, 0.0, None, None

    def quantile(q: float) -> float:
        target = q * count
        prev_le = 0.0
        prev_c = 0.0
        for le_s, cum in sorted(
            buckets.items(), key=lambda x: float("inf") if x[0] == "+Inf" else float(x[0])
        ):
            le = float("inf") if le_s == "+Inf" else float(le_s)
            if cum >= target:
                if cum == prev_c:
                    return le
                frac = (target - prev_c) / (cum - prev_c)
                return prev_le + frac * (le - prev_le)
            prev_le, prev_c = le, cum
        return total / count

    return count, total / count, quantile(0.5), quantile(0.95)


def parse_gauge(text: str, pattern: str) -> int | None:
    for line in text.splitlines():
        if pattern in line and not line.startswith("#"):
            try:
                return int(float(line.rsplit(" ", 1)[-1]))
            except ValueError:
                pass
    return None


def parse_subnet_gauges(text: str, section: str) -> dict[int, int]:
    out: dict[int, int] = {}
    pat = f'section="{section}",subnet="subnet_'
    for line in text.splitlines():
        if not line.startswith("lean_attestation_aggregate_coverage_validators"):
            continue
        if pat not in line:
            continue
        m = re.search(r'subnet="subnet_(\d+)"\}\s+(\S+)', line)
        if m:
            out[int(m.group(1))] = int(float(m.group(2)))
    return out


def parse_labeled_counter(text: str, prefix: str, label: str) -> int:
    pat = f'{prefix}{{reason="{label}"}}'
    for line in text.splitlines():
        if line.startswith(pat):
            return int(float(line.rsplit(" ", 1)[-1]))
    return 0


def parse_counter(text: str, name: str) -> int:
    for line in text.splitlines():
        if not line.startswith(name):
            continue
        rest = line[len(name) :]
        if rest.startswith(" ") or rest.startswith("\t"):
            return int(float(line.rsplit(" ", 1)[-1]))
    return 0


def parse_publish_counter(text: str, client: str) -> int:
    prefixes = [
        "zeam_aggregator_publish_aggregations_total",
        "lean_aggregator_publish_aggregations_total",
    ]
    total = 0
    for line in text.splitlines():
        if any(line.startswith(p) for p in prefixes):
            total += int(float(line.rsplit(" ", 1)[-1]))
    # fallback: any metric with publish and aggregation in name
    if total == 0:
        for line in text.splitlines():
            low = line.lower()
            if "publish" in low and "aggregat" in low and not line.startswith("#"):
                if "_total" in line or "_count" in line:
                    try:
                        total += int(float(line.rsplit(" ", 1)[-1]))
                    except ValueError:
                        pass
    return total


def analyze_logs(log_text: str) -> dict[str, Any]:
    cur_slot: int | None = None
    lags: list[int] = []
    agg_starts = 0
    in_flight = 0
    coalesced = 0
    publishes = 0

    for line in log_text.splitlines():
        m = re.search(r"\[s=(\d+) i=(\d+)\]", line)
        if m:
            cur_slot = int(m.group(1))
        if "agg start slot=" in line:
            agg_starts += 1
        if "already in flight" in line or "skipping aggregation for slot=" in line:
            in_flight += 1
        if "coalescing aggregation for slot=" in line:
            coalesced += 1
        m = re.search(
            r"published aggregation to network: slot=(\d+)|publish.*aggregat.*slot[= ](\d+)",
            line,
            re.I,
        )
        if m and cur_slot is not None:
            att_slot = int(m.group(1) or m.group(2))
            lags.append(cur_slot - att_slot)
            publishes += 1

    result: dict[str, Any] = {
        "agg_starts": agg_starts,
        "in_flight": in_flight,
        "coalesced": coalesced,
        "publishes": publishes,
    }
    if lags:
        lags.sort()
        n = len(lags)
        on_time = sum(1 for x in lags if x <= 2)
        result.update(
            {
                "lag_n": n,
                "lag_p50": lags[n // 2],
                "lag_mean": sum(lags) / n,
                "lag_max": lags[-1],
                "on_time_pct": 100.0 * on_time / n,
            }
        )
    return result


def analyze_agg(info: AggInfo, ssh_key: str, log_since: str) -> AggReport:
    rep = AggReport(info=info)

    # container image
    ps = ssh_cmd(
        ssh_key,
        info.ip,
        f"docker ps --format '{{{{.Names}}}} {{{{.Image}}}}' | grep -E '{info.name}|zeam-{info.name}' | head -1",
    ).strip()
    if ps:
        rep.container_image = ps.split(" ", 1)[-1] if " " in ps else ps

    try:
        body = fetch_metrics(info.ip, info.metrics_port)
        rep.metrics_ok = True
    except Exception as e:
        rep.errors.append(f"metrics: {e}")
        body = ""

    if body:
        # worker duration — zeam-specific first, then generic building time as proxy
        for metric, label in [
            ("zeam_aggregate_worker_duration_seconds", "zeam_worker"),
            ("lean_pq_sig_aggregated_signatures_building_time_seconds", "build_per_att_data"),
        ]:
            count, mean, p50, _ = hist_stats(body, metric)
            if count > 0 and rep.worker_mean_s is None and metric.startswith("zeam_aggregate"):
                rep.worker_metric = metric
                rep.worker_count = count
                rep.worker_mean_s = mean
                rep.worker_p50_s = p50
            if metric.endswith("building_time_seconds") and count > 0:
                rep.build_count = count
                rep.build_mean_s = mean

        if rep.worker_mean_s is None:
            count, mean, p50, _ = hist_stats(
                body, "lean_pq_sig_aggregated_signatures_building_time_seconds"
            )
            if count > 0:
                rep.worker_metric = "lean_pq_sig_aggregated_signatures_building_time_seconds (proxy)"
                rep.worker_count = count
                rep.worker_mean_s = mean
                rep.worker_p50_s = p50

        _, ffi_mean, _, _ = hist_stats(
            body, "zeam_pq_sig_aggregated_signatures_building_phase_seconds"
        )
        # phase histogram has label — parse compute_ffi specifically
        ffi_buckets: dict[str, float] = {}
        ffi_count = 0
        ffi_sum = 0.0
        for line in body.splitlines():
            if 'phase="compute_ffi"' not in line:
                continue
            if "_bucket" in line and line.startswith(
                "zeam_pq_sig_aggregated_signatures_building_phase_seconds_bucket"
            ):
                le = line.split('le="')[1].split('"')[0]
                ffi_buckets[le] = float(line.rsplit(" ", 1)[-1])
            elif line.startswith(
                "zeam_pq_sig_aggregated_signatures_building_phase_seconds_count{phase=\"compute_ffi\"}"
            ):
                ffi_count = int(float(line.rsplit(" ", 1)[-1]))
            elif line.startswith(
                "zeam_pq_sig_aggregated_signatures_building_phase_seconds_sum{phase=\"compute_ffi\"}"
            ):
                ffi_sum = float(line.rsplit(" ", 1)[-1])
        if ffi_count > 0:
            rep.compute_ffi_mean_s = ffi_sum / ffi_count

        rep.skip_in_flight = parse_labeled_counter(body, "zeam_aggregate_skip_total", "in_flight")
        rep.coalesced_total = parse_counter(body, "zeam_aggregate_coalesced_total")
        rep.publish_total = parse_publish_counter(body, info.client)

        rep.timely_combined = parse_gauge(
            body, 'section="timely",subnet="combined"'
        )
        rep.late_combined = parse_gauge(body, 'section="late",subnet="combined"')
        rep.combined_combined = parse_gauge(body, 'section="combined",subnet="combined"')
        rep.timely_by_subnet = parse_subnet_gauges(body, "timely")
        rep.late_by_subnet = parse_subnet_gauges(body, "late")
        rep.combined_by_subnet = parse_subnet_gauges(body, "combined")

    log = ssh_cmd(
        ssh_key,
        info.ip,
        f"docker logs --since {log_since} {info.name} 2>&1 || docker logs --since {log_since} zeam-{info.name} 2>&1 || true",
        timeout=45,
    )
    if log:
        la = analyze_logs(log)
        rep.log_agg_starts = la.get("agg_starts", 0)
        rep.log_in_flight = la.get("in_flight", 0)
        rep.log_coalesced = la.get("coalesced", 0)
        rep.log_publishes = la.get("publishes", 0)
        if "lag_n" in la:
            rep.publish_lag_n = la["lag_n"]
            rep.publish_lag_p50 = la["lag_p50"]
            rep.publish_lag_mean = la["lag_mean"]
            rep.publish_on_time_pct = la["on_time_pct"]

    return rep


def fmt_s(v: float | None) -> str:
    return f"{v:.2f}s" if v is not None else "n/a"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--validator-config",
        default="ansible-devnet/genesis/validator-config.yaml",
    )
    ap.add_argument("--ssh-key", default=f"{__import__('os').environ.get('HOME', '')}/.ssh/id_ed25519_github")
    ap.add_argument("--log-since", default="30m")
    args = ap.parse_args()

    aggs = load_aggregators(args.validator_config)
    reports = [analyze_agg(a, args.ssh_key, args.log_since) for a in aggs]

    print(f"# Subnet aggregation report (log window: {args.log_since})")
    print()

    # Table 1: aggregator performance
    print("## Aggregator prove/publish performance")
    print(
        "| Subnet | Aggregator | Client | Worker/prove mean | p50 | compute_ffi (zeam) | coalesced | publishes (logs) | publish lag p50 | on-time (lag≤2) |"
    )
    print("|---:|---|---|---:|---:|---:|---:|---:|---:|---:|")
    for r in reports:
        i = r.info
        coalesce_rate = ""
        denom = r.log_agg_starts + r.log_coalesced
        if denom > 0:
            coalesce_rate = f" ({100*r.log_coalesced/denom:.0f}%)"
        print(
            f"| {i.subnet} | {i.name} | {i.client} | {fmt_s(r.worker_mean_s)} | {fmt_s(r.worker_p50_s)} | {fmt_s(r.compute_ffi_mean_s)} | {r.coalesced_total or r.log_coalesced}{coalesce_rate} | {r.log_publishes or r.publish_total} | {r.publish_lag_p50 if r.publish_lag_p50 is not None else 'n/a'} | {f'{r.publish_on_time_pct:.0f}%' if r.publish_on_time_pct is not None else 'n/a'} |"
        )

    print()
    print("## Subnet receive timeliness (latest coverage gauge on each aggregator)")
    print("Timely = peer aggregate in merge buffer before i=0/i=4. Late = arrived after merge window.")
    print()
    print("| Subnet | Aggregator | timely (own obs) | late | combined | receives on-time? |")
    print("|---:|---|---:|---:|---:|---|")
    for r in reports:
        i = r.info
        timely = r.timely_combined
        late = r.late_combined
        comb = r.combined_combined
        if timely is None and not r.metrics_ok:
            status = "no metrics"
        elif timely and timely > 0:
            status = "YES (some timely)"
        elif comb and comb > 0 and (timely or 0) == 0:
            status = "NO (only late)"
        elif comb == 0 or comb is None:
            status = "NO (none seen)"
        else:
            status = "marginal"
        print(
            f"| {i.subnet} | {i.name} | {timely if timely is not None else '?'} | {late if late is not None else '?'} | {comb if comb is not None else '?'} | {status} |"
        )

    # Cross-subnet view from zeam_8 (subnet 0 aggregator sees peer subnets via gossip aggregates)
    zeam8 = next((r for r in reports if r.info.subnet == 0), None)
    if zeam8 and (zeam8.timely_by_subnet or zeam8.late_by_subnet):
        print()
        print("## Cross-subnet visibility from zeam_8 (subnet 0 aggregator)")
        print("| Subnet | timely validators | late validators | combined | on-time? |")
        print("|---:|---:|---:|---:|---|")
        for sn in range(8):
            t = zeam8.timely_by_subnet.get(sn, 0)
            l = zeam8.late_by_subnet.get(sn, 0)
            c = zeam8.combined_by_subnet.get(sn, 0)
            if t > 0:
                st = "YES"
            elif c > 0:
                st = "NO (late only)"
            else:
                st = "none seen"
            print(f"| {sn} | {t} | {l} | {c} | {st} |")

    print()
    print("## Summary")
    on_time_aggs = [
        r for r in reports if r.publish_on_time_pct is not None and r.publish_on_time_pct >= 50
    ]
    slow_aggs = [r for r in reports if r.worker_mean_s is not None and r.worker_mean_s > 6]
    print(
        f"- Aggregators publishing ≥50% within 2 slots: {', '.join(r.info.name for r in on_time_aggs) or 'none'}"
    )
    print(
        f"- Aggregators with mean prove/worker time >6s (slot budget): {', '.join(f'{r.info.name} ({r.worker_mean_s:.1f}s)' for r in slow_aggs) or 'none'}"
    )
    timely_subnets = [r.info.subnet for r in reports if (r.timely_combined or 0) > 0]
    print(
        f"- Subnets with any timely peer coverage at aggregator: {timely_subnets or 'none'}"
    )


if __name__ == "__main__":
    main()
