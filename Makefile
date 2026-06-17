export ROOT_DIR := $(CURDIR)
export SCRIPTS_DIR := $(ROOT_DIR)/scripts
FOUNDATION_DIR := $(SCRIPTS_DIR)/pulumi/foundation
CLUSTER_DIR := $(SCRIPTS_DIR)/pulumi/cluster

.PHONY: create

destroy:
	@$(MAKE) destroy-$(word 2,$(MAKECMDGOALS))

create:
	@$(MAKE) create-$(word 2,$(MAKECMDGOALS))

%:
	@:

configure:
	./scripts/configure.sh

create-universe:
	./scripts/create.sh

wireguard:
	./scripts/wireguard/setup.sh

create-cluster:
	cd "$(CLUSTER_DIR)" && "$(SCRIPTS_DIR)/pulumi/pulumi-up.sh"
	cd "$(CLUSTER_DIR)" && "$(SCRIPTS_DIR)/merge-kubeconfig.sh"
	cd "$(CLUSTER_DIR)" && "$(SCRIPTS_DIR)/generate-env.sh"
	"$(SCRIPTS_DIR)/generate-values.sh"

destroy-universe:
	./scripts/destroy.sh
