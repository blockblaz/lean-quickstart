#!/bin/bash
# setup-tools-server.sh: Ensure Docker on tools server(s) and install tool images (e.g. blockblaz/leanpoint:latest)
# Tools server(s) are defined in ansible/inventory/tools_servers.yml (separate from validator nodes).

set -e

scriptPath="$0"
if [ -L "$scriptPath" ]; then
  scriptPath=$(readlink "$scriptPath")
  if [ "${scriptPath:0:1}" != "/" ]; then
    scriptPath="$(dirname "$0")/$scriptPath"
  fi
fi
scriptDir=$(cd "$(dirname "$scriptPath")" && pwd)

# Defaults
sshKeyFile=""
useRoot="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sshKey)
      sshKeyFile="$2"
      shift 2
      ;;
    --useRoot)
      useRoot="true"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--sshKey PATH] [--useRoot]"
      exit 1
      ;;
  esac
done

if [ "$useRoot" == "true" ]; then
  sshUser="root"
else
  sshUser=$(whoami)
fi

ANSIBLE_DIR="$scriptDir/ansible"
TOOLS_INVENTORY="$ANSIBLE_DIR/inventory/tools_servers.yml"
PLAYBOOK="playbooks/setup-tools-server.yml"

if [ ! -f "$TOOLS_INVENTORY" ]; then
  echo "Error: Tools server inventory not found at $TOOLS_INVENTORY"
  exit 1
fi

if [ ! -f "$ANSIBLE_DIR/$PLAYBOOK" ]; then
  echo "Error: Playbook not found at $ANSIBLE_DIR/$PLAYBOOK"
  exit 1
fi

# Update tools_servers hosts with SSH user and key if provided
if command -v yq &> /dev/null; then
  hosts=$(yq eval ".all.children.tools_servers.hosts | keys | .[]" "$TOOLS_INVENTORY" 2>/dev/null || echo "")
  for host in $hosts; do
    yq eval -i ".all.children.tools_servers.hosts.$host.ansible_user = \"$sshUser\"" "$TOOLS_INVENTORY"
    if [ -n "$sshKeyFile" ]; then
      if [[ "$sshKeyFile" == ~* ]]; then
        sshKeyFile="${sshKeyFile/#\~/$HOME}"
      fi
      yq eval -i ".all.children.tools_servers.hosts.$host.ansible_ssh_private_key_file = \"$sshKeyFile\"" "$TOOLS_INVENTORY"
      echo "Setting SSH private key for $host: $sshKeyFile"
    fi
  done
fi

echo "Setting up tools server(s) (Docker + tool images)..."
echo "SSH user: $sshUser"
echo ""

cd "$ANSIBLE_DIR"
ansible-playbook -i inventory/tools_servers.yml "playbooks/setup-tools-server.yml"

EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
  echo ""
  echo "✅ Tools server setup completed successfully!"
else
  echo ""
  echo "❌ Tools server setup failed with exit code $EXIT_CODE"
fi
exit $EXIT_CODE
