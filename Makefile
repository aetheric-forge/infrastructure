export ROOT_DIR := $(CURDIR)
export SCRIPTS_DIR := $(ROOT_DIR)/scripts
FOUNDATION_DIR := $(SCRIPTS_DIR)/pulumi/foundation
CLUSTER_DIR := $(SCRIPTS_DIR)/pulumi/cluster

STAGES := foundation wireguard cluster platform step-ca verify

.PHONY: create destroy configure wireguard create-universe destroy-universe \
	create-platform-services debug-cluster $(addprefix create-,$(STAGES)) $(addprefix create-from-,$(STAGES))

destroy:
	@$(MAKE) destroy-$(word 2,$(MAKECMDGOALS))

# `make create <stage>` runs one stage of scripts/create.sh;
# `make create from-<stage>` runs that stage and everything after it.
create:
	@$(MAKE) create-$(word 2,$(MAKECMDGOALS))

%:
	@:

configure:
	./scripts/configure.sh

create-universe:
	./scripts/create.sh

$(addprefix create-,$(STAGES)): create-%:
	./scripts/create.sh --only $*

$(addprefix create-from-,$(STAGES)): create-from-%:
	./scripts/create.sh --from $*

create-platform-services:
	./scripts/create.sh --platform-services

wireguard: create-wireguard

debug-cluster:
	./scripts/debug-cluster.sh

destroy-universe:
	./scripts/destroy.sh
