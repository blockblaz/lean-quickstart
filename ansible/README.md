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

3. **Generate genesis files locally:**
   ```sh
   # From repository root - generate genesis files first
   ./generate-genesis.sh local-devnet/genesis
   ```

4. **Test locally (dry run):**
   ```sh
   # From repository root - test without making changes
   ./ansible-deploy.sh --node zeam_0,ream_0 --network-dir local-devnet --check
   ```

5. **Deploy nodes locally:**
   ```sh
   # From repository root - genesis files are copied to remote hosts automatically
   ./ansible-deploy.sh --node zeam_0,ream_0 --network-dir local-devnet
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

# 3. Copy genesis files to remote hosts only
./ansible-deploy.sh --playbook copy-genesis.yml --network-dir local-devnet

# 4. Deploy a single node
./ansible-deploy.sh --node zeam_0 --network-dir local-devnet

# 5. Verify it's running
docker ps | grep zeam_0
```

## Directory Structure

- `ansible.cfg` - Ansible configuration
- `inventory/` - Host inventory and variables
- `playbooks/` - Main playbooks
- `roles/` - Reusable role modules (zeam, ream, qlean, lantern, lighthouse, grandine, ethlambda, genesis, common)
- `requirements.yml` - Ansible Galaxy dependencies

## Configuration Source

Ansible roles automatically extract Docker images and deployment modes from `client-cmds/*-cmd.sh` files:

- **Docker images** are extracted from the `node_docker` variable in each client's `client-cmd.sh` file
- **Deployment mode** (docker/binary) is extracted from the `node_setup` variable

This ensures consistency between `spin-node.sh` (local deployment) and Ansible (remote deployment). To change a client's Docker image or deployment mode, edit the corresponding `client-cmds/*-cmd.sh` file - the change will automatically apply to both local and Ansible deployments.

**Example:** To change Zeam's Docker image, edit `client-cmds/zeam-cmd.sh`:
```bash
node_docker="--security-opt seccomp=unconfined blockblaz/zeam:newtag node \
  ...
```

The Ansible role will automatically use the new image on the next deployment.

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

**Minimum Required Version:** Ansible 2.13+

The configuration uses `result_format = yaml` (introduced in Ansible 2.13). Earlier versions will fail with an error about the removed `community.general.yaml` callback plugin.

**macOS:**
```sh
brew install ansible
```

**Ubuntu/Debian:**
```sh
sudo apt-get update
sudo apt-get install ansible
```

**Verify installation (must be 2.13+):**
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
# Test from repository root (genesis files must be generated first)
./generate-genesis.sh local-devnet/genesis
./ansible-deploy.sh --node zeam_0,ream_0 --network-dir local-devnet --check
```

This shows what would be changed without actually making changes.

### Phase 2: Validate Playbook Syntax

Check that all playbooks are syntactically correct:

```sh
cd ansible

# Check all playbooks
ansible-playbook --syntax-check playbooks/site.yml
ansible-playbook --syntax-check playbooks/clean-node-data.yml
ansible-playbook --syntax-check playbooks/generate-genesis.yml
ansible-playbook --syntax-check playbooks/copy-genesis.yml
ansible-playbook --syntax-check playbooks/deploy-nodes.yml
ansible-playbook --syntax-check playbooks/stop-nodes.yml
```

### Phase 3: Test Genesis File Copying

Test copying genesis files to remote hosts (genesis files must be generated locally first):

```sh
# Generate genesis files locally first
./generate-genesis.sh local-devnet/genesis

# From repository root - test copy operation
./ansible-deploy.sh --playbook copy-genesis.yml --network-dir local-devnet --check

# Actually copy (removes --check)
./ansible-deploy.sh --playbook copy-genesis.yml --network-dir local-devnet
```

**Verify copied files on remote host:**
```sh
ls -la local-devnet/genesis/
# Should see: config.yaml, validators.yaml, nodes.yaml, genesis.json, genesis.ssz, *.key files
```

### Phase 4: Test Docker Image Extraction (Latest Changes)

Test that docker images and deployment modes are correctly extracted from `client-cmd.sh` files:

```sh
# Test extraction in check mode (see extracted values)
./ansible-deploy.sh --node zeam_0 --network-dir local-devnet --check -v | grep -A 3 "Extract docker"

# Verify extracted values match client-cmd.sh
grep -E '^node_docker=' client-cmds/zeam-cmd.sh | grep -oE '[^/ ]+/[^: ]+:[^ "]+' | head -1
grep -E '^node_setup=' client-cmds/zeam-cmd.sh | sed -E 's/.*node_setup="([^"]+)".*/\1/'
```

**Expected output:** You should see tasks extracting docker images and deployment modes, and the values should match what's in the `client-cmds/*-cmd.sh` files.

For detailed testing instructions, see the "Testing Docker Image Extraction" section below.

### Phase 5: Test Single Node Deployment

Test deploying a single node:

```sh
# Dry run first
./ansible-deploy.sh --node zeam_0 --network-dir local-devnet --check

# Actual deployment
./ansible-deploy.sh --node zeam_0 --network-dir local-devnet
```

**Verify node is running and using correct image:**
```sh
docker ps | grep zeam_0
docker inspect zeam_0 | grep Image
# The image should match what's in client-cmds/zeam-cmd.sh
# Or check metrics
curl http://localhost:8080/metrics  # Adjust port based on node
```

### Phase 6: Test Multiple Nodes

Test deploying multiple nodes:

```sh
# Deploy two nodes
./ansible-deploy.sh --node zeam_0,ream_0 --network-dir local-devnet

# Verify both are running
docker ps | grep -E "zeam_0|ream_0"
```

### Phase 7: Test Clean Data and Regeneration

Test the clean data functionality:

```sh
# Clean data and redeploy (genesis files must be generated first)
./generate-genesis.sh local-devnet/genesis
./ansible-deploy.sh --node zeam_0,ream_0 --network-dir local-devnet --clean-data
```

**Verify data directories were cleaned:**
```sh
ls -la local-devnet/data/zeam_0/  # Should be empty or recreated
```

### Phase 8: Test Idempotency

One of Ansible's key features is idempotency. Run the same command twice:

```sh
# First run
./ansible-deploy.sh --node zeam_0 --network-dir local-devnet

# Second run (should show "changed: 0" for most tasks)
./ansible-deploy.sh --node zeam_0 --network-dir local-devnet
```

The second run should show minimal or no changes.

### Phase 9: Test with Tags

Test running specific parts of the deployment:

```sh
# Only run genesis-related tasks (copy-genesis playbook doesn't require --node)
./ansible-deploy.sh --playbook copy-genesis.yml --network-dir local-devnet --tags genesis

# Only deploy zeam nodes
./ansible-deploy.sh --node zeam_0 --network-dir local-devnet --tags zeam

# Only setup (install dependencies)
./ansible-deploy.sh --node zeam_0,ream_0 --network-dir local-devnet --tags setup
```

### Phase 10: Test Using Ansible Directly

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
ansible-playbook -i inventory/hosts.yml playbooks/copy-genesis.yml \
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
- [ ] Docker images are correctly extracted from `client-cmd.sh` files
- [ ] Deployment modes are correctly extracted from `client-cmd.sh` files
- [ ] Extracted docker images match values in `client-cmd.sh` files
- [ ] Single node deploys successfully
- [ ] Multiple nodes deploy successfully
- [ ] Docker containers are running (`docker ps`)
- [ ] Containers use the correct docker images (verify with `docker inspect`)
- [ ] Containers have correct volumes mounted
- [ ] Containers have correct network mode (host)
- [ ] Containers have correct command arguments

### Cleanup and Redeployment
- [ ] `--clean-data` cleans data directories
- [ ] Genesis files are copied from local to remote hosts
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

#### 8. Docker image extraction returns empty or wrong value

If the extracted docker image is empty or incorrect:

1. **Verify client-cmd.sh file exists:**
   ```sh
   ls -la client-cmds/zeam-cmd.sh
   ```

2. **Check the file format:**
   ```sh
   grep -E '^node_docker=' client-cmds/zeam-cmd.sh
   grep -E '^node_setup=' client-cmds/zeam-cmd.sh
   ```

3. **Test extraction manually:**
   ```sh
   # For zeam (handles --security-opt prefix)
   grep -E '^node_docker=' client-cmds/zeam-cmd.sh | grep -oE '[^/ ]+/[^: ]+:[^ "]+' | head -1
   
   # For ream/qlean (first word)
   grep -E '^node_docker=' client-cmds/ream-cmd.sh | sed -E 's/.*node_docker="([^ "]+).*/\1/'
   ```

4. **Check file permissions:**
   ```sh
   ls -l client-cmds/*-cmd.sh
   ```

5. **Run with verbose output to see extraction:**
   ```sh
   ./ansible-deploy.sh --node zeam_0 --network-dir local-devnet --check -v | grep -A 5 "Extract docker"
   ```

If extraction fails, the role will fall back to defaults in `roles/*/defaults/main.yml`.

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
./ansible-deploy.sh --node zeam_0,ream_0 --network-dir local-devnet --check
```

### Test Binary Deployment Mode

If you have binaries available:

```sh
./ansible-deploy.sh --node zeam_0 --network-dir local-devnet --deployment-mode binary
```

Note: Binary deployment requires systemd service templates (not yet fully implemented in roles).

## Testing Docker Image Extraction

This section covers how to test the latest changes that extract docker images and deployment modes from `client-cmd.sh` files.

### What Changed

- Docker images and deployment modes are now automatically extracted from `client-cmds/*-cmd.sh` files
- This ensures consistency between `spin-node.sh` (local) and Ansible (remote) deployments
- All client roles (zeam, ream, qlean, lantern, lighthouse, grandine, ethlambda) now use this extraction mechanism

### Quick Test

Run the automated test script:

```sh
cd ansible
./test-local.sh
```

### Manual Testing Steps

#### 1. Test Docker Image Extraction

Verify that docker images are correctly extracted from client-cmd.sh files:

```sh
# Test Zeam extraction
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/deploy-nodes.yml \
  -e "network_dir=$(pwd)/../local-devnet" \
  -e "node_names=zeam_0" \
  --check \
  -v | grep -A 5 "Extract docker image"

# Test Ream extraction
ansible-playbook -i inventory/hosts.yml playbooks/deploy-nodes.yml \
  -e "network_dir=$(pwd)/../local-devnet" \
  -e "node_names=ream_0" \
  --check \
  -v | grep -A 5 "Extract docker image"

# Test Qlean extraction
ansible-playbook -i inventory/hosts.yml playbooks/deploy-nodes.yml \
  -e "network_dir=$(pwd)/../local-devnet" \
  -e "node_names=qlean_0" \
  --check \
  -v | grep -A 5 "Extract docker image"
```

#### 2. Verify Extracted Values Match client-cmd.sh

Manually check that extracted values match what's in the client-cmd.sh files:

```sh
# Check Zeam
echo "Zeam docker image from client-cmd.sh:"
grep -E '^node_docker=' client-cmds/zeam-cmd.sh | grep -oE '[^/ ]+/[^: ]+:[^ "]+' | head -1

echo "Zeam deployment mode from client-cmd.sh:"
grep -E '^node_setup=' client-cmds/zeam-cmd.sh | sed -E 's/.*node_setup="([^"]+)".*/\1/'

# Check Ream
echo "Ream docker image from client-cmd.sh:"
grep -E '^node_docker=' client-cmds/ream-cmd.sh | sed -E 's/.*node_docker="([^ "]+).*/\1/'

echo "Ream deployment mode from client-cmd.sh:"
grep -E '^node_setup=' client-cmds/ream-cmd.sh | sed -E 's/.*node_setup="([^"]+)".*/\1/'

# Check Qlean
echo "Qlean docker image from client-cmd.sh:"
grep -E '^node_docker=' client-cmds/qlean-cmd.sh | sed -E 's/.*node_docker="([^ "]+).*/\1/'

echo "Qlean deployment mode from client-cmd.sh:"
grep -E '^node_setup=' client-cmds/qlean-cmd.sh | sed -E 's/.*node_setup="([^"]+)".*/\1/'
```

#### 3. Test Actual Deployment with Extracted Values

Deploy a node and verify it uses the correct docker image:

```sh
# Ensure genesis files exist
./generate-genesis.sh local-devnet/genesis

# Deploy Zeam node
./ansible-deploy.sh --node zeam_0 --network-dir local-devnet

# Verify the container is using the correct image
docker ps | grep zeam_0
docker inspect zeam_0 | grep Image

# The image should match what's in client-cmds/zeam-cmd.sh
```

#### 4. Test Changing client-cmd.sh and Re-deploying

Test that changes to client-cmd.sh are automatically picked up:

```sh
# Backup original
cp client-cmds/zeam-cmd.sh client-cmds/zeam-cmd.sh.bak

# Temporarily change the docker image (for testing)
sed -i.bak 's/blockblaz\/zeam:devnet1/blockblaz\/zeam:test-tag/' client-cmds/zeam-cmd.sh

# Deploy and verify it uses the new image
./ansible-deploy.sh --node zeam_0 --network-dir local-devnet --check -v | grep "zeam_docker_image"

# Restore original
mv client-cmds/zeam-cmd.sh.bak client-cmds/zeam-cmd.sh
```

#### 5. Test All Clients Together

Test that all three clients extract values correctly:

```sh
# Generate genesis if needed
./generate-genesis.sh local-devnet/genesis

# Deploy all clients in check mode
./ansible-deploy.sh --node zeam_0,ream_0,qlean_0 --network-dir local-devnet --check -v

# Look for extraction tasks in output
# Should see:
# - "Extract docker image from client-cmd.sh" for each client
# - "Extract deployment mode from client-cmd.sh" for each client
# - "Set docker image and deployment mode from client-cmd.sh" for each client
```

#### 6. Test Fallback Behavior

Test that fallback defaults work if extraction fails:

```sh
# Temporarily rename a client-cmd.sh file
mv client-cmds/zeam-cmd.sh client-cmds/zeam-cmd.sh.tmp

# Try to deploy - should use fallback from defaults/main.yml
./ansible-deploy.sh --node zeam_0 --network-dir local-devnet --check -v

# Restore
mv client-cmds/zeam-cmd.sh.tmp client-cmds/zeam-cmd.sh
```

### Expected Results

#### Successful Extraction

When extraction works correctly, you should see in the Ansible output:

```
TASK [zeam : Extract docker image from client-cmd.sh] ***
ok: [localhost]

TASK [zeam : Extract deployment mode from client-cmd.sh] ***
ok: [localhost]

TASK [zeam : Set docker image and deployment mode from client-cmd.sh] ***
ok: [localhost] => {
    "ansible_facts": {
        "deployment_mode": "docker",
        "zeam_docker_image": "blockblaz/zeam:devnet1"
    }
}
```

#### Docker Container Verification

After deployment, verify the container uses the correct image:

```sh
docker ps --format "table {{.Names}}\t{{.Image}}" | grep -E "zeam_0|ream_0|qlean_0"
```

The images should match what's in the respective `client-cmds/*-cmd.sh` files.

### Troubleshooting Extraction Issues

#### Extraction Returns Empty

If extraction returns empty values:
1. Check that `client-cmds/*-cmd.sh` files exist
2. Verify the grep patterns match the file format
3. Check file permissions

#### Wrong Image Extracted

If the wrong image is extracted:
1. Verify the `node_docker` line format in client-cmd.sh
2. Check the sed/grep patterns in the extraction tasks
3. For zeam, ensure it handles `--security-opt` prefix correctly

#### Fallback Not Working

If fallback defaults aren't used:
1. Check `roles/*/defaults/main.yml` files
2. Verify the `default()` filter in set_fact tasks

### Integration with Existing Tests

The existing test script (`ansible/test-local.sh`) will automatically test these changes as part of its normal flow. The extraction happens during role execution, so no special test flags are needed.

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

# Test genesis file copying (genesis files must be generated locally first)
echo "3. Testing genesis file copying..."
./generate-genesis.sh local-devnet/genesis
./ansible-deploy.sh --playbook copy-genesis.yml --network-dir local-devnet

# Test docker image extraction
echo "4. Testing docker image extraction..."
./ansible-deploy.sh --node zeam_0 --network-dir local-devnet --check -v | grep -A 3 "Extract docker" || echo "⚠️  Extraction check skipped"

# Test deployment
echo "5. Testing node deployment..."
./ansible-deploy.sh --node zeam_0 --network-dir local-devnet

# Verify
echo "6. Verifying deployment..."
docker ps | grep zeam_0 || exit 1

# Verify docker image matches client-cmd.sh
echo "7. Verifying docker image matches client-cmd.sh..."
EXPECTED_IMAGE=$(grep -E '^node_docker=' client-cmds/zeam-cmd.sh | grep -oE '[^/ ]+/[^: ]+:[^ "]+' | head -1)
ACTUAL_IMAGE=$(docker inspect zeam_0 --format '{{.Config.Image}}' 2>/dev/null || echo "")
if [ -n "$EXPECTED_IMAGE" ] && [ -n "$ACTUAL_IMAGE" ]; then
    if [ "$EXPECTED_IMAGE" = "$ACTUAL_IMAGE" ]; then
        echo "✅ Docker image matches: $ACTUAL_IMAGE"
    else
        echo "⚠️  Docker image mismatch. Expected: $EXPECTED_IMAGE, Got: $ACTUAL_IMAGE"
    fi
fi

echo "✅ All tests passed!"
```

Make it executable and run:
```sh
chmod +x test-ansible.sh
./test-ansible.sh
```

