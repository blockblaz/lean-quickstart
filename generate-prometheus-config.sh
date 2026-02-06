#!/bin/bash
# Generate prometheus.yml from validator-config.yaml
# Reads all validators and creates scrape targets using host.docker.internal
#
# Usage: ./generate-prometheus-config.sh <validator-config.yaml> <output-dir>
# Example: ./generate-prometheus-config.sh local-devnet/genesis/validator-config.yaml metrics/prometheus

set -e

validator_config="$1"
output_dir="$2"

if [ -z "$validator_config" ] || [ -z "$output_dir" ]; then
    echo "Usage: $0 <validator-config.yaml> <output-dir>"
    exit 1
fi

if [ ! -f "$validator_config" ]; then
    echo "Error: Validator config not found at $validator_config"
    exit 1
fi

if ! command -v yq &> /dev/null; then
    echo "Error: yq is required but not installed."
    exit 1
fi

mkdir -p "$output_dir"

# Extract node names and metrics ports
node_count=$(yq eval '.validators | length' "$validator_config")

# Build scrape configs
scrape_configs=""
for ((i=0; i<node_count; i++)); do
    name=$(yq eval ".validators[$i].name" "$validator_config")
    port=$(yq eval ".validators[$i].metricsPort" "$validator_config")

    if [ -z "$name" ] || [ "$name" == "null" ] || [ -z "$port" ] || [ "$port" == "null" ]; then
        echo "Warning: Skipping validator $i (missing name or metricsPort)"
        continue
    fi

    scrape_configs="${scrape_configs}
  - job_name: \"${name}\"
    static_configs:
      - targets: [\"host.docker.internal:${port}\"]
        labels:
          client: \"${name}\"
          instance: \"local\""
done

# Write prometheus.yml
cat > "$output_dir/prometheus.yml" << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    monitor: "lean-devnet-metrics"

scrape_configs:
${scrape_configs}

  # Prometheus self-monitoring
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]
EOF

echo "Generated $output_dir/prometheus.yml with $node_count scrape targets"
