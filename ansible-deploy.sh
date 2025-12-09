#!/bin/bash
# Ansible-based deployment wrapper for Lean Quickstart
# Provides similar interface to spin-node.sh but uses Ansible

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$SCRIPT_DIR/ansible"

# Default values
NODE_NAMES=""
CLEAN_DATA=""
NETWORK_DIR=""
VALIDATOR_CONFIG=""
DEPLOYMENT_MODE="docker"
EXTRA_VARS=""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Ansible-based deployment for Lean Quickstart nodes.

Options:
  --node NODES              Node(s) to deploy:
                              - Single node: 'zeam_0'
                              - Multiple nodes: 'zeam_0,ream_0' or 'zeam_0 ream_0'
  --network-dir DIR         Network directory (default: local-devnet)
  --clean-data              Clean data directories before deployment
  --validator-config PATH   Path to validator-config.yaml (default: genesis_bootnode)
  --deployment-mode MODE    Deployment mode: 'docker' or 'binary' (default: docker)
  --playbook PLAYBOOK       Ansible playbook to run (default: site.yml)
                              Options: site.yml, genesis.yml, deploy-nodes.yml, copy-genesis.yml
  --tags TAGS               Run only tasks with specific tags (comma-separated)
  --check                   Dry run (check mode)
  --diff                    Show file changes
  --verbose                 Verbose output
  -h, --help                Show this help message

Examples:
  # Deploy specific nodes (genesis files copied from local)
  $0 --node zeam_0,ream_0 --network-dir local-devnet

  # Deploy a single node
  $0 --node zeam_0 --network-dir local-devnet

  # Copy genesis files to remote hosts only
  $0 --playbook copy-genesis.yml --network-dir local-devnet

  # Deploy with dry run
  $0 --node zeam_0,ream_0 --check

Environment Variables:
  NETWORK_DIR               Network directory (overrides --network-dir)

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --node)
            NODE_NAMES="$2"
            shift 2
            ;;
        --network-dir)
            NETWORK_DIR="$2"
            shift 2
            ;;
        --clean-data)
            CLEAN_DATA="true"
            shift
            ;;
        --validator-config)
            VALIDATOR_CONFIG="$2"
            shift 2
            ;;
        --deployment-mode)
            DEPLOYMENT_MODE="$2"
            shift 2
            ;;
        --playbook)
            PLAYBOOK="$2"
            shift 2
            ;;
        --tags)
            TAGS="$2"
            shift 2
            ;;
        --check)
            CHECK_MODE="--check"
            shift
            ;;
        --diff)
            DIFF_MODE="--diff"
            shift
            ;;
        --verbose|-v)
            VERBOSE="-vvv"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

# Validate Ansible prerequisites
# Note: These checks are also performed in spin-node.sh when routing to Ansible
# This ensures prerequisites are available when ansible-deploy.sh is executed directly
if ! command -v ansible-playbook &> /dev/null; then
    echo -e "${RED}Error: ansible-playbook is not installed.${NC}"
    echo "Install Ansible:"
    echo "  macOS:   brew install ansible"
    echo "  Ubuntu:  sudo apt-get install ansible"
    echo "  pip:     pip install ansible"
    exit 1
fi

if ! ansible-galaxy collection list | grep -q "community.docker" 2>/dev/null; then
    echo -e "${YELLOW}Warning: community.docker collection not found. Installing...${NC}"
    ansible-galaxy collection install community.docker
fi

# Use NETWORK_DIR from environment if not provided
if [ -z "$NETWORK_DIR" ]; then
    if [ -n "$NETWORK_DIR_ENV" ]; then
        NETWORK_DIR="$NETWORK_DIR_ENV"
    else
        NETWORK_DIR="local-devnet"
    fi
fi

# Convert NETWORK_DIR to absolute path
NETWORK_DIR_ABS="$(cd "$SCRIPT_DIR" && cd "$NETWORK_DIR" > /dev/null 2>&1 && pwd || echo "$SCRIPT_DIR/$NETWORK_DIR")"

# Default playbook
PLAYBOOK="${PLAYBOOK:-site.yml}"

# Build extra-vars
EXTRA_VARS="network_dir=$NETWORK_DIR_ABS"

if [ -n "$NODE_NAMES" ]; then
    EXTRA_VARS="$EXTRA_VARS node_names=$NODE_NAMES"
fi

if [ -n "$CLEAN_DATA" ]; then
    EXTRA_VARS="$EXTRA_VARS clean_data=true"
fi

if [ -n "$VALIDATOR_CONFIG" ]; then
    EXTRA_VARS="$EXTRA_VARS validator_config=$VALIDATOR_CONFIG"
fi

EXTRA_VARS="$EXTRA_VARS deployment_mode=$DEPLOYMENT_MODE"

# Build ansible-playbook command
ANSIBLE_CMD="ansible-playbook"
ANSIBLE_CMD="$ANSIBLE_CMD -i $ANSIBLE_DIR/inventory/hosts.yml"
ANSIBLE_CMD="$ANSIBLE_CMD $ANSIBLE_DIR/playbooks/$PLAYBOOK"
ANSIBLE_CMD="$ANSIBLE_CMD -e \"$EXTRA_VARS\""

if [ -n "$TAGS" ]; then
    ANSIBLE_CMD="$ANSIBLE_CMD --tags $TAGS"
fi

if [ -n "$CHECK_MODE" ]; then
    ANSIBLE_CMD="$ANSIBLE_CMD --check"
fi

if [ -n "$DIFF_MODE" ]; then
    ANSIBLE_CMD="$ANSIBLE_CMD --diff"
fi

if [ -n "$VERBOSE" ]; then
    ANSIBLE_CMD="$ANSIBLE_CMD $VERBOSE"
fi

# Display configuration
echo -e "${GREEN}Ansible Deployment Configuration:${NC}"
echo "  Playbook:        $PLAYBOOK"
echo "  Network Directory: $NETWORK_DIR_ABS"
echo "  Nodes:           ${NODE_NAMES:-<not specified>}"
echo "  Clean Data:      ${CLEAN_DATA:-false}"
echo "  Deployment Mode: $DEPLOYMENT_MODE"
echo "  Check Mode:      ${CHECK_MODE:-false}"
echo ""

# Change to Ansible directory
cd "$ANSIBLE_DIR"

# Execute Ansible playbook
echo -e "${GREEN}Running Ansible playbook...${NC}"
echo ""

eval $ANSIBLE_CMD

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ Deployment completed successfully!${NC}"
else
    echo ""
    echo -e "${RED}❌ Deployment failed with exit code $EXIT_CODE${NC}"
    exit $EXIT_CODE
fi

