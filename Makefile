LAB     := 01-hello-world
LAB_DIR := labs/$(LAB)
TOPO    := $(LAB_DIR)/topology.yml

# With prefix: "" in the topology, container names are just the node names.
CEOS_CONTAINER  := ceos1
SONIC_CONTAINER := sonic1

.PHONY: help deploy destroy inspect connect-ceos connect-sonic config-sonic graph get-sonic

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Image management:"
	@echo "  get-sonic      Download latest SONiC VS image (auto-detects newest release)"
	@echo ""
	@echo "Lab lifecycle:"
	@echo "  deploy         Deploy the $(LAB) lab"
	@echo "  destroy        Destroy the $(LAB) lab"
	@echo "  inspect        Show running nodes and management IPs"
	@echo "  graph          Generate an interactive HTML topology diagram"
	@echo ""
	@echo "Node access:"
	@echo "  connect-ceos   Open EOS CLI on ceos1"
	@echo "  connect-sonic  Open bash shell on sonic1"
	@echo "  config-sonic   Re-apply sonic1-config.json and reload SONiC"
	@echo ""
	@echo "Set LAB=<dir> to target a different lab, e.g.: make deploy LAB=02-bgp"
	@echo "Set SONIC_BRANCH=202411 to pin a specific SONiC release branch"

deploy:
	clab deploy --topo $(TOPO) --reconfigure

destroy:
	clab destroy --topo $(TOPO) --cleanup

inspect:
	clab inspect --topo $(TOPO)

connect-ceos:
	docker exec -it $(CEOS_CONTAINER) Cli

connect-sonic:
	docker exec -it $(SONIC_CONTAINER) bash

config-sonic:
	docker cp $(LAB_DIR)/configs/sonic1-config.json $(SONIC_CONTAINER):/etc/sonic/config_db.json
	docker exec $(SONIC_CONTAINER) sudo config reload -y

graph:
	clab graph --topo $(TOPO)

get-sonic:
	bash scripts/get-sonic-vs.sh --load $(if $(SONIC_BRANCH),--branch $(SONIC_BRANCH),)
