#!/bin/bash

# Test script for zeam with local image
echo "========================================="
echo "Testing zeam with 0xpartha/zeam:local"
echo "========================================="

# Clean up any existing containers
echo "Cleaning up existing zeam_0 container..."
docker rm -f zeam_0 2>/dev/null || true

# Run with local-devnet configuration
echo ""
echo "Starting zeam_0 with devnet3 configuration..."
echo "- Image: 0xpartha/zeam:local"
echo "- Aggregator: Will be randomly selected"
echo "- Attestation committee count: Using client default (not overridden)"
echo ""

NETWORK_DIR=local-devnet ./spin-node.sh --node zeam_0 --generateGenesis --cleanData

