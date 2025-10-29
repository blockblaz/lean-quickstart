# Ansible Deployment for Lean Quickstart

This directory contains Ansible playbooks and roles for deploying Lean blockchain nodes.

For detailed documentation, see the [main README](../README.md#ansible-deployment).

## Quick Start

1. **Install Ansible:**
   ```sh
   # macOS
   brew install ansible
   
   # Ubuntu/Debian
   sudo apt-get install ansible
   ```

2. **Install Ansible dependencies:**
   ```sh
   ansible-galaxy install -r requirements.yml
   ```

3. **Deploy nodes:**
   ```sh
   # From repository root
   ./ansible-deploy.sh --node all --network-dir local-devnet --generate-genesis
   ```

## Directory Structure

- `ansible.cfg` - Ansible configuration
- `inventory/` - Host inventory and variables
- `playbooks/` - Main playbooks
- `roles/` - Reusable role modules
- `requirements.yml` - Ansible Galaxy dependencies

## Usage

See the main README for complete usage instructions, or run:

```sh
./ansible-deploy.sh --help
```

