#!/bin/bash
set -e

echo "Setting up SONiC Lab Workbook environment..."

# Enable containerlab bash completion
sudo containerlab completion bash > /etc/bash_completion.d/containerlab 2>/dev/null || true

# Add vscode user to docker group so clab can run without sudo
# (the docker-outside-of-docker feature may already handle this)
if getent group docker > /dev/null 2>&1; then
    sudo usermod -aG docker "${USER}" 2>/dev/null || true
fi

echo ""
echo "Environment is ready."
echo ""
echo "Next steps:"
echo "  1. Import lab images — see README.md > 'Importing Lab Images'"
echo "  2. Verify images:   docker images | grep -E 'ceos|sonic'"
echo "  3. Deploy the lab:  make deploy"
echo ""
