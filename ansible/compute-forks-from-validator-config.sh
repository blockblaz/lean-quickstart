#!/usr/bin/env bash
# Emit an integer for ansible-playbook --forks based on unique enrFields.ip
# values in validator-config.yaml (one row per logical machine in typical layouts).
#
# Usage: compute-forks-from-validator-config.sh /abs/or/rel/path/to/validator-config.yaml
#
# Environment (optional):
#   LEAN_ANSIBLE_FORKS_MIN  floor after counting unique IPs (default: 5). Helps when
#                           many inventory hosts share one IP so work is not fully serialized.
#   LEAN_ANSIBLE_FORKS_MAX  ceiling (default: 128)
#   LEAN_ANSIBLE_FORKS_FALLBACK  if the file is missing, yq fails, or count is 0 (default: 25)

set -euo pipefail

vc_path="${1:-}"
_min="${LEAN_ANSIBLE_FORKS_MIN:-5}"
_max="${LEAN_ANSIBLE_FORKS_MAX:-128}"
_fallback="${LEAN_ANSIBLE_FORKS_FALLBACK:-25}"

if [[ -z "$vc_path" ]]; then
  echo "$_fallback"
  exit 0
fi

if [[ ! -f "$vc_path" ]]; then
  echo "$_fallback"
  exit 0
fi

if ! command -v yq &>/dev/null; then
  echo "$_fallback"
  exit 0
fi

unique_ips=0
if ! unique_ips=$(yq eval '[.validators[]? | .enrFields.ip // "" | select(. != "")] | unique | length' "$vc_path" 2>/dev/null); then
  echo "$_fallback"
  exit 0
fi

# yq may print nothing on some failures
if [[ -z "${unique_ips// /}" ]] || ! [[ "$unique_ips" =~ ^[0-9]+$ ]]; then
  echo "$_fallback"
  exit 0
fi

if (( unique_ips < 1 )); then
  echo "$_fallback"
  exit 0
fi

forks=$unique_ips
if (( forks < _min )); then
  forks=$_min
fi
if (( forks > _max )); then
  forks=$_max
fi

echo "$forks"
