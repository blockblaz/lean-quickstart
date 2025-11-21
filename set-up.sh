#!/bin/bash
# set -e

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
  
  # Find the genesis generator script
  genesis_generator="$scriptDir/generate-genesis.sh"
  
  if [ ! -f "$genesis_generator" ]; then
    echo "❌ Error: Genesis generator not found at $genesis_generator"
    exit 1
  fi
  
  # Run the generator
  if ! $genesis_generator "$configDir" "$FORCE_KEYGEN_FLAG"; then
    echo "❌ Genesis generation failed!"
    exit 1
  fi
  
  echo "================================================"
  echo ""
fi

