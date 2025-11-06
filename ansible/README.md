# Ansible Deployment for Lean Quickstart

This directory contains Ansible playbooks and roles for deploying Lean blockchain nodes.

For detailed documentation, see the [main README](../README.md#ansible-deployment).

## Deployment Modes

This Ansible setup supports two deployment modes:

1. **Docker** (default) - Deploy containers directly on hosts
2. **Binary** - Deploy binaries as systemd services

## Quick Start

### Docker (Default)

1. **Install Ansible:**
   ```sh
   # macOS
   brew install ansible
   
   # Ubuntu/Debian
   sudo apt-get install ansible
   ```

2. **Install Ansible dependencies:**
   ```sh
   cd ansible
   ansible-galaxy install -r requirements.yml
   ```

3. **Test locally (dry run):**
   ```sh
   # From repository root - test without making changes
   ./ansible-deploy.sh --node all --network-dir local-devnet --generate-genesis --check
   ```

4. **Deploy nodes locally:**
   ```sh
   # From repository root
   ./ansible-deploy.sh --node all --network-dir local-devnet --generate-genesis
   ```

## Quick Local Testing

Test Ansible setup locally with the provided script:

```sh
cd ansible
./test-local.sh
```

Or test manually:

```sh
# 1. Check syntax
cd ansible
ansible-playbook --syntax-check playbooks/site.yml

# 2. Dry run (see what would change)
cd ..
./ansible-deploy.sh --node zeam_0 --network-dir local-devnet --check

# 3. Generate genesis files only
./ansible-deploy.sh --playbook genesis.yml --network-dir local-devnet

# 4. Deploy a single node
./ansible-deploy.sh --node zeam_0 --network-dir local-devnet

# 5. Verify it's running
docker ps | grep zeam_0
```

## Directory Structure

- `ansible.cfg` - Ansible configuration
- `inventory/` - Host inventory and variables
- `playbooks/` - Main playbooks
- `roles/` - Reusable role modules (zeam, ream, qlean, genesis, common)
- `requirements.yml` - Ansible Galaxy dependencies

## Usage

See the main README for complete usage instructions, or run:

```sh
./ansible-deploy.sh --help
```

---

# Testing Ansible Deployment

This guide covers comprehensive testing strategies for the Ansible deployment infrastructure.

## Prerequisites

### 1. Install Ansible

**macOS:**
```sh
brew install ansible
```

**Ubuntu/Debian:**
```sh
sudo apt-get update
sudo apt-get install ansible
```

**Verify installation:**
```sh
ansible --version
ansible-playbook --version
```

### 2. Install Ansible Dependencies

```sh
cd ansible
ansible-galaxy install -r requirements.yml
```

This installs the `community.docker` collection required for Docker operations.

### 3. Verify Docker is Running

```sh
docker --version
docker ps  # Should work without errors
```

## Testing Strategies

### Phase 1: Dry Run (Check Mode)

Start with a dry run to see what Ansible would do without making changes:

```sh
# Test from repository root
./ansible-deploy.sh --node all --network-dir local-devnet --generate-genesis --check
```

This shows what would be changed without actually making changes.

### Phase 2: Validate Playbook Syntax

Check that all playbooks are syntactically correct:

```sh
cd ansible

# Check all playbooks
ansible-playbook --syntax-check playbooks/site.yml
ansible-playbook --syntax-check playbooks/genesis.yml
ansible-playbook --syntax-check playbooks/deploy-nodes.yml
```

### Phase 3: Test Genesis Generation Only

Test genesis file generation in isolation:

```sh
# From repository root
./ansible-deploy.sh --playbook genesis.yml --network-dir local-devnet --check

# Actually generate (removes --check)
./ansible-deploy.sh --playbook genesis.yml --network-dir local-devnet
```

**Verify generated files:**
```sh
ls -la local-devnet/genesis/
# Should see: config.yaml, validators.yaml, nodes.yaml, genesis.json, genesis.ssz, *.key files
```

### Phase 4: Test Single Node Deployment

Test deploying a single node:

```sh
# Dry run first
./ansible-deploy.sh --node zeam_0 --network-dir local-devnet --check

# Actual deployment
./ansible-deploy.sh --node zeam_0 --network-dir local-devnet
```

**Verify node is running:**
```sh
docker ps | grep zeam_0
# Or check metrics
curl http://localhost:8080/metrics  # Adjust port based on node
```

### Phase 5: Test Multiple Nodes

Test deploying multiple nodes:

```sh
# Deploy two nodes
./ansible-deploy.sh --node zeam_0,ream_0 --network-dir local-devnet

# Verify both are running
docker ps | grep -E "zeam_0|ream_0"
```

### Phase 6: Test Clean Data and Regeneration

Test the clean data functionality:

```sh
# Clean and regenerate
./ansible-deploy.sh --node all --network-dir local-devnet --clean-data --generate-genesis
```

**Verify data directories were cleaned:**
```sh
ls -la local-devnet/data/zeam_0/  # Should be empty or recreated
```

### Phase 7: Test Idempotency

One of Ansible's key features is idempotency. Run the same command twice:

```sh
# First run
./ansible-deploy.sh --node zeam_0 --network-dir local-devnet

# Second run (should show "changed: 0" for most tasks)
./ansible-deploy.sh --node zeam_0 --network-dir local-devnet
```

The second run should show minimal or no changes.

### Phase 8: Test with Tags

Test running specific parts of the deployment:

```sh
# Only run genesis-related tasks
./ansible-deploy.sh --node all --network-dir local-devnet --tags genesis

# Only deploy zeam nodes
./ansible-deploy.sh --node zeam_0 --network-dir local-devnet --tags zeam

# Only setup (install dependencies)
./ansible-deploy.sh --node all --network-dir local-devnet --tags setup
```

### Phase 9: Test Using Ansible Directly

Test running Ansible playbooks directly without the wrapper:

```sh
cd ansible

# Run with verbose output
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  -e "network_dir=$(pwd)/../local-devnet" \
  -e "node_names=zeam_0" \
  -e "generate_genesis=true" \
  -v

# Run with diff to see file changes
ansible-playbook -i inventory/hosts.yml playbooks/genesis.yml \
  -e "network_dir=$(pwd)/../local-devnet" \
  --diff
```

## Testing Checklist

Use this checklist to verify everything works:

### Pre-Deployment
- [ ] Ansible is installed and working
- [ ] Docker is running and accessible
- [ ] yq is installed and in PATH
- [ ] Ansible collections installed (`ansible-galaxy collection list`)

### Genesis Generation
- [ ] `validator-config.yaml` exists in network directory
- [ ] Genesis generation completes without errors
- [ ] All required files are generated:
  - [ ] `config.yaml`
  - [ ] `validators.yaml`
  - [ ] `nodes.yaml`
  - [ ] `genesis.json`
  - [ ] `genesis.ssz`
  - [ ] `*.key` files for each node

### Node Deployment
- [ ] Single node deploys successfully
- [ ] Multiple nodes deploy successfully
- [ ] All nodes deploy successfully (--node all)
- [ ] Docker containers are running (`docker ps`)
- [ ] Containers have correct volumes mounted
- [ ] Containers have correct network mode (host)
- [ ] Containers have correct command arguments

### Cleanup and Regeneration
- [ ] `--clean-data` cleans data directories
- [ ] `--generate-genesis` regenerates genesis files
- [ ] Combined flags work correctly

### Verification
- [ ] Node metrics ports are accessible
- [ ] Node logs show no errors
- [ ] Nodes can peer discover each other (for multi-node)
- [ ] Idempotency works (rerun shows no changes)

## Troubleshooting

### Common Issues

#### 1. "community.docker collection not found"

```sh
cd ansible
ansible-galaxy collection install community.docker
```

#### 2. "yq not found"

```sh
# macOS
brew install yq

# Linux - install from GitHub releases
# https://github.com/mikefarah/yq#install
```

#### 3. "Docker connection refused"

Check Docker is running:
```sh
docker ps
# If fails, start Docker Desktop or Docker daemon
```

#### 4. "Permission denied" for Docker

On Linux, add user to docker group:
```sh
sudo usermod -aG docker $USER
# Log out and back in
```

Or use sudo (not recommended):
```sh
./ansible-deploy.sh --node zeam_0 --network-dir local-devnet --docker-with-sudo
```

#### 5. "Node not found in validator-config.yaml"

Ensure node name matches exactly in `validator-config.yaml`:
```sh
yq eval '.validators[].name' local-devnet/genesis/validator-config.yaml
```

#### 6. Container starts but immediately exits

Check container logs:
```sh
docker logs zeam_0
# Look for errors in the logs
```

Verify genesis files exist:
```sh
ls -la local-devnet/genesis/
```

#### 7. Port conflicts

Check if ports are already in use:
```sh
# Check QUIC port (default 9000)
lsof -i :9000

# Check metrics port (default 8080)
lsof -i :8080
```

Stop conflicting containers or change ports in `validator-config.yaml`.

## Advanced Testing

### Test with Verbose Output

Get detailed output for debugging:

```sh
./ansible-deploy.sh --node zeam_0 --network-dir local-devnet --verbose
```

### Test Remote Deployment (If Configured)

1. Update `ansible/inventory/hosts.yml` with remote hosts
2. Ensure SSH key authentication works:
```sh
ssh -i ~/.ssh/id_rsa user@remote-host "echo 'Connection successful'"
```
3. Test with check mode first:
```sh
./ansible-deploy.sh --node all --network-dir local-devnet --check
```

### Test Binary Deployment Mode

If you have binaries available:

```sh
./ansible-deploy.sh --node zeam_0 --network-dir local-devnet --deployment-mode binary
```

Note: Binary deployment requires systemd service templates (not yet fully implemented in roles).

## Continuous Testing

For automated testing, you could create a test script:

```sh
#!/bin/bash
# test-ansible.sh

set -e

echo "Testing Ansible deployment..."

# Test syntax
echo "1. Checking playbook syntax..."
cd ansible
ansible-playbook --syntax-check playbooks/site.yml

# Test dry run
echo "2. Running dry run..."
cd ..
./ansible-deploy.sh --node zeam_0 --network-dir local-devnet --check

# Test genesis generation
echo "3. Testing genesis generation..."
./ansible-deploy.sh --playbook genesis.yml --network-dir local-devnet

# Test deployment
echo "4. Testing node deployment..."
./ansible-deploy.sh --node zeam_0 --network-dir local-devnet

# Verify
echo "5. Verifying deployment..."
docker ps | grep zeam_0 || exit 1

echo "✅ All tests passed!"
```

Make it executable and run:
```sh
chmod +x test-ansible.sh
./test-ansible.sh
```

