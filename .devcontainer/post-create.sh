#!/bin/bash
set -e

echo "Setting up SONiC Lab Workbook environment..."

# Install Python networking libraries.
# Doing this here (not in the Dockerfile) keeps image builds fast.
pip3 install --quiet --no-cache-dir -r "$(dirname "$0")/requirements.txt"

# Enable containerlab bash completion
containerlab completion bash | sudo tee /etc/bash_completion.d/containerlab > /dev/null

echo ""
echo "Environment is ready."
echo ""
echo "Next steps:"
echo "  1. Import lab images — see README.md > 'Importing Lab Images'"
echo "  2. Verify:  docker images | grep -E 'ceos|sonic'"
echo "  3. Deploy:  clab deploy --topo labs/01-hello-world/topology.yml"
echo ""
