#!/bin/bash
set -e

echo "Setting up SONiC Lab Workbook environment..."

# Install Python networking libraries.
# Doing this here (not in the Dockerfile) keeps image builds fast.
pip3 install --quiet --no-cache-dir -r "$(dirname "$0")/requirements.txt"

# Enable containerlab bash completion
containerlab completion bash | sudo tee /etc/bash_completion.d/containerlab > /dev/null

# Add vscode to the 'docker' group. This group is created at runtime by the
# docker-outside-of-docker feature with the GID matching the host Docker socket,
# so it cannot be added in the Dockerfile build step.
if getent group docker > /dev/null 2>&1; then
    sudo usermod -aG docker "${USER}"
fi

echo ""
echo "Environment is ready."
echo ""
echo "ACTION REQUIRED: reload this VS Code window to apply group membership"
echo "changes (needed for the containerlab extension and sudo-less docker)."
echo "  Command Palette → 'Developer: Reload Window'  (Ctrl+Shift+P / Cmd+Shift+P)"
echo ""
echo "Then:"
echo "  1. Import lab images — see README.md > 'Importing Lab Images'"
echo "  2. Verify:  docker images | grep -E 'ceos|sonic'"
echo "  3. Deploy:  clab deploy --topo labs/01-hello-world/topology.yml"
echo ""
