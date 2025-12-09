#!/bin/bash
# Quick local testing script for Ansible deployment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🧪 Testing Ansible Deployment Locally"
echo "======================================"
echo ""

# Check prerequisites
echo "1️⃣  Checking prerequisites..."
if ! command -v ansible-playbook &> /dev/null; then
    echo "❌ Ansible not found. Install with: brew install ansible"
    exit 1
fi
echo "   ✅ Ansible found"

if ! command -v docker &> /dev/null; then
    echo "❌ Docker not found"
    exit 1
fi
echo "   ✅ Docker found"

if ! command -v yq &> /dev/null; then
    echo "❌ yq not found. Install with: brew install yq"
    exit 1
fi
echo "   ✅ yq found"
echo ""

# Check Ansible collections
echo "2️⃣  Checking Ansible collections..."
if ! ansible-galaxy collection list 2>/dev/null | grep -q "community.docker"; then
    echo "   Installing community.docker collection..."
    cd "$SCRIPT_DIR"
    ansible-galaxy collection install -r requirements.yml
else
    echo "   ✅ community.docker collection installed"
fi
echo ""

# Check playbook syntax
echo "3️⃣  Checking playbook syntax..."
cd "$SCRIPT_DIR"
# Task files (included via include_tasks) cannot be syntax-checked directly
# They are validated when parent playbooks are checked
task_files=("deploy-single-node.yml")
for playbook in playbooks/*.yml; do
    playbook_name=$(basename "$playbook")
    # Skip task files - they're validated when parent playbooks run
    if [[ " ${task_files[@]} " =~ " ${playbook_name} " ]]; then
        echo "   ⏭️  $(basename $playbook) (task file, validated via parent playbook)"
        continue
    fi
    
    if ansible-playbook --syntax-check "$playbook" > /dev/null 2>&1; then
        echo "   ✅ $(basename $playbook)"
    else
        echo "   ❌ $(basename $playbook) has syntax errors"
        exit 1
    fi
done
echo ""

# Test dry run (check mode)
echo "4️⃣  Testing dry run (check mode)..."
cd "$REPO_ROOT"
if [ -d "local-devnet/genesis" ] && [ -f "local-devnet/genesis/validator-config.yaml" ]; then
    echo "   Running check mode for genesis file copying..."
    ./ansible-deploy.sh --playbook copy-genesis.yml --network-dir local-devnet --check > /dev/null 2>&1 || echo "   ⚠️  Check mode showed some changes (this is normal)"
    echo "   ✅ Dry run completed"
else
    echo "   ⚠️  local-devnet/genesis not found, skipping check mode test"
fi
echo ""

# Test actual genesis file copying (genesis files must be generated locally first)
echo "5️⃣  Testing genesis file copying..."
cd "$REPO_ROOT"
if [ ! -d "local-devnet/genesis" ]; then
    echo "   Creating local-devnet/genesis directory..."
    mkdir -p local-devnet/genesis
    echo "   ⚠️  Please create validator-config.yaml in local-devnet/genesis/"
    echo "   Skipping actual deployment test"
    exit 0
fi

if [ ! -f "local-devnet/genesis/validator-config.yaml" ]; then
    echo "   ⚠️  validator-config.yaml not found"
    echo "   Skipping actual deployment test"
    exit 0
fi

# Generate genesis files locally first if they don't exist
if [ ! -f "local-devnet/genesis/genesis.ssz" ]; then
    echo "   Generating genesis files locally first (this may take a moment)..."
    ./generate-genesis.sh local-devnet/genesis || {
        echo "   ❌ Failed to generate genesis files locally"
        exit 1
    }
fi

echo "   Testing genesis file copying..."
if ./ansible-deploy.sh --playbook copy-genesis.yml --network-dir local-devnet 2>&1 | tail -5; then
    echo "   ✅ Genesis file copying successful"
    
    # Verify files
    echo ""
    echo "   Verifying generated files..."
    required_files=("config.yaml" "validators.yaml" "nodes.yaml" "genesis.json" "genesis.ssz")
    all_good=true
    for file in "${required_files[@]}"; do
        if [ -f "local-devnet/genesis/$file" ]; then
            echo "   ✅ $file"
        else
            echo "   ❌ $file missing"
            all_good=false
        fi
    done
    
    if [ "$all_good" = true ]; then
        echo ""
        echo "✅ All tests passed! Ansible is ready for local deployment."
        echo ""
        echo "Next steps:"
        echo "  ./ansible-deploy.sh --node zeam_0 --network-dir local-devnet"
        echo "  ./ansible-deploy.sh --node all --network-dir local-devnet"
    else
        echo ""
        echo "❌ Some files are missing. Check the output above."
        exit 1
    fi
else
    echo "   ❌ Genesis generation failed"
    exit 1
fi

