LAB      := 01-hello-world
LAB_DIR  := labs/$(LAB)
TOPO     := $(LAB_DIR)/topology.yml

.PHONY: help deploy destroy inspect connect-ceos connect-sonic graph

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "  deploy         Deploy the $(LAB) lab"
	@echo "  destroy        Destroy the $(LAB) lab"
	@echo "  inspect        Show running lab nodes and their IPs"
	@echo "  connect-ceos   Open EOS CLI on ceos1"
	@echo "  connect-sonic  Open bash shell on sonic1"
	@echo "  graph          Generate a topology diagram (HTML)"
	@echo ""
	@echo "Set LAB=<dir> to target a different lab, e.g.:"
	@echo "  make deploy LAB=02-bgp"

deploy:
	sudo clab deploy --topo $(TOPO) --reconfigure

destroy:
	sudo clab destroy --topo $(TOPO) --cleanup

inspect:
	sudo clab inspect --all

connect-ceos:
	docker exec -it clab-$(LAB)-ceos1 Cli

connect-sonic:
	docker exec -it clab-$(LAB)-sonic1 bash

graph:
	sudo clab graph --topo $(TOPO)
