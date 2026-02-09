# Testing devnet3 Configuration

## Setup

The local-devnet has been configured to test devnet3 features with the local zeam image.

### Changes Made:

1. **zeam-cmd.sh**: Updated to use `0xpartha/zeam:local` image
2. **local-devnet/validator-config.yaml**: Added commented attestation_committee_count parameter

## devnet3 Features Being Tested

### 1. Automatic Aggregator Selection
- One node will be randomly selected as aggregator on startup
- The `isAggregator` flag in validator-config.yaml will be automatically updated
- Only the selected aggregator will receive `--is-aggregator` flag

### 2. Optional Attestation Committee Count
- Currently commented out (clients use hardcoded default)
- Can be enabled by uncommenting: `attestation_committee_count: 1`
- When set, all clients receive `--attestation-committee-count <value>` flag

## Test Commands

### Basic Test - Single Node (zeam_0)
```bash
# Run the test script
./test-local-zeam.sh

# Or manually:
NETWORK_DIR=local-devnet ./spin-node.sh --node zeam_0 --generateGenesis --cleanData
```

### Test with Manual Aggregator Selection
```bash
# Specify zeam_0 as aggregator
NETWORK_DIR=local-devnet ./spin-node.sh --node zeam_0 --generateGenesis --cleanData --aggregator zeam_0
```

### Test Multiple Nodes
```bash
# Run all nodes (zeam_0 will be randomly selected as aggregator)
NETWORK_DIR=local-devnet ./spin-node.sh --node all --generateGenesis --cleanData

# Run specific nodes with zeam_0 as aggregator
NETWORK_DIR=local-devnet ./spin-node.sh --node "zeam_0 ream_0" --generateGenesis --cleanData --aggregator zeam_0
```

### Test with Attestation Committee Count Override
```bash
# 1. Uncomment attestation_committee_count in local-devnet/genesis/validator-config.yaml
# 2. Set desired value (e.g., attestation_committee_count: 4)
# 3. Run:
NETWORK_DIR=local-devnet ./spin-node.sh --node zeam_0 --generateGenesis --cleanData
```

## Expected Behavior

### Aggregator Selection
1. Script displays: "Randomly selected aggregator: zeam_0 (index 0 out of 7 nodes)" OR "Using user-specified aggregator: zeam_0"
2. Script updates validator-config.yaml: sets `isAggregator: true` for selected node
3. parse-vc.sh output shows: "Is Aggregator: true" for aggregator, "false" for others
4. zeam command includes `--is-aggregator` flag for aggregator only

### Attestation Committee Count
**When NOT set (default):**
- parse-vc.sh does NOT display "Attestation Committee Count"
- zeam command does NOT include `--attestation-committee-count` flag
- Client uses its hardcoded default

**When set (e.g., to 4):**
- parse-vc.sh displays: "Attestation Committee Count: 4"
- zeam command includes: `--attestation-committee-count 4`
- Client uses the specified value

## Verification

### Check Docker Container
```bash
# Inspect the running container
docker inspect zeam_0

# Check container logs
docker logs zeam_0

# Verify command-line arguments
docker inspect zeam_0 | grep -A20 Args
```

### Check Configuration
```bash
# Verify aggregator selection in validator-config.yaml
yq eval '.validators[] | select(.name == "zeam_0") | .isAggregator' local-devnet/genesis/validator-config.yaml

# Check all aggregators
yq eval '.validators[] | select(.isAggregator == true) | .name' local-devnet/genesis/validator-config.yaml
```

### Monitor Node Output
```bash
# Watch zeam_0 logs in real-time
docker logs -f zeam_0

# Check for aggregator-related messages
docker logs zeam_0 2>&1 | grep -i aggregat
```

## Cleanup

```bash
# Stop and remove zeam_0 container
docker rm -f zeam_0

# Stop all nodes
NETWORK_DIR=local-devnet ./spin-node.sh --node all --stop

# Clean data directories
rm -rf local-devnet/data/*
```

## Troubleshooting

### Image Not Found
If you get "image not found" error:
```bash
# Check if image exists
docker images | grep zeam

# Pull/build the image if needed
# (build instructions depend on your zeam setup)
```

### Port Conflicts
If ports are already in use:
```bash
# Check what's using the port
lsof -i :8081  # zeam_0 metrics port
lsof -i :9001  # zeam_0 QUIC port

# Kill conflicting processes or change ports in validator-config.yaml
```

### Genesis Generation Fails
```bash
# Ensure yq is installed
brew install yq  # macOS
# or follow: https://github.com/mikefarah/yq#install

# Check validator-config.yaml syntax
yq eval . local-devnet/genesis/validator-config.yaml
```

## Notes

- The `0xpartha/zeam:local` image should have the latest devnet3 changes
- All devnet3 features (aggregator selection, optional attestation_committee_count) are enabled
- The configuration is set up for local testing with 127.0.0.1 IPs
- Hash-sig keys will be generated automatically on first run with `--generateGenesis`
