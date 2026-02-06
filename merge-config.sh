#!/bin/bash
# Merge user-config.yml overrides into validator-config.yaml
# Creates deploy-validator-config.yaml in the same directory as the base config
#
# Usage: ./merge-config.sh <validator-config.yaml> [user-config.yml]
#
# If user-config.yml is not provided or doesn't exist, the base config is copied as-is.

set -e

base_config="$1"      # validator-config.yaml (required)
user_config="$2"      # user-config.yml (optional)

if [ -z "$base_config" ]; then
  echo "Usage: $0 <validator-config.yaml> [user-config.yml]"
  exit 1
fi

if [ ! -f "$base_config" ]; then
  echo "Error: Base config not found: $base_config"
  exit 1
fi

# Check if yq is installed
if ! command -v yq &> /dev/null; then
  echo "Error: yq is required but not installed."
  exit 1
fi

# Output file is in the same directory as base config
config_dir=$(dirname "$base_config")
output_config="$config_dir/deploy-validator-config.yaml"

# Start with base config
cp "$base_config" "$output_config"

# If no user config provided or doesn't exist, we're done
if [ -z "$user_config" ] || [ ! -f "$user_config" ]; then
  echo "✓ Created deploy-validator-config.yaml (no user overrides)"
  exit 0
fi

echo "Merging user config overrides from $user_config..."

# Get all node names from user config
node_names=$(yq eval '.validators[].name' "$user_config" 2>/dev/null)

if [ -z "$node_names" ]; then
  echo "✓ Created deploy-validator-config.yaml (no validators in user config)"
  exit 0
fi

override_count=0

for node in $node_names; do
  # Check if this node exists in base config
  node_exists=$(yq eval ".validators[] | select(.name == \"$node\") | .name" "$output_config" 2>/dev/null)
  if [ -z "$node_exists" ] || [ "$node_exists" == "null" ]; then
    echo "  ⚠ Skipping $node: not found in validator-config.yaml"
    continue
  fi

  # Merge image if specified
  image=$(yq eval ".validators[] | select(.name == \"$node\") | .image // \"\"" "$user_config" 2>/dev/null)
  if [ -n "$image" ] && [ "$image" != "null" ] && [ "$image" != "" ]; then
    yq eval -i "(.validators[] | select(.name == \"$node\")).image = \"$image\"" "$output_config"
    echo "  ✓ $node: image = $image"
    ((override_count++))
  fi

  # Add more mergeable fields here as needed
done

echo "✓ Created deploy-validator-config.yaml ($override_count override(s) applied)"
