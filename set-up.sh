#!/bin/bash
# set -e

# Default deployment_mode to local if not set by parent script
deployment_mode="${deployment_mode:-local}"

# ========================================
# Step 1: Generate genesis files if needed
# ========================================
# Run genesis generator if:
# - --generateGenesis flag is set, OR
# - validators.yaml doesn't exist, OR
# - nodes.yaml doesn't exist
if [ -n "$generateGenesis" ] || [ ! -f "$configDir/validators.yaml" ] || [ ! -f "$configDir/nodes.yaml" ]; then
  echo ""
  echo "🔧 Running genesis generator..."
  echo "================================================"
  
  # Ensure genesis directory exists (may not exist when using an external NETWORK_DIR)
  mkdir -p "$configDir"

  # Find the genesis generator script
  genesis_generator="$scriptDir/generate-genesis.sh"
  
  if [ ! -f "$genesis_generator" ]; then
    echo "❌ Error: Genesis generator not found at $genesis_generator"
    exit 1
  fi
  
  # Pass external validator config if provided (not the default genesis_bootnode sentinel)
  _validator_config_flag=""
  if [ -n "$validatorConfig" ] && [ "$validatorConfig" != "genesis_bootnode" ]; then
    _validator_config_flag="--validator-config $validatorConfig"
  fi

  # Run the generator with deployment mode
  if ! $genesis_generator "$configDir" --mode "$deployment_mode" $FORCE_KEYGEN_FLAG $_validator_config_flag; then
    echo "❌ Genesis generation failed!"
    exit 1
  fi
  
  echo "================================================"
  echo ""
fi

