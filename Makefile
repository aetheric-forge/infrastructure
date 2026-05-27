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

create-foundation:
	cd "$(FOUNDATION_DIR)" && "$(SCRIPTS_DIR)/pulumi/pulumi-up.sh"
	cd "$(FOUNDATION_DIR)" && "$(SCRIPTS_DIR)/generate-env.sh"
	"$(SCRIPTS_DIR)/generate-values.sh"

wireguard:
	./scripts/wireguard/setup.sh

create-cluster:
	cd "$(CLUSTER_DIR)" && "$(SCRIPTS_DIR)/pulumi/pulumi-up.sh"
	cd "$(CLUSTER_DIR)" && "$(SCRIPTS_DIR)/merge-kubeconfig.sh"
	cd "$(CLUSTER_DIR)" && "$(SCRIPTS_DIR)/generate-env.sh"
	"$(SCRIPTS_DIR)/generate-values.sh"

create-gitops:
	./scripts/utils/validate-kustomize.sh
	kubectl apply -f "$(ROOT_DIR)/platform/external-dns/base/namespaces.yaml"
	kustomize build --enable-helm --enable-alpha-plugins --enable-exec "$(ROOT_DIR)/clusters/single/dev" | kubectl apply -f -
	kubectl -n argocd apply -f "$(ROOT_DIR)/platform/argocd/bootstrap/dev-root-application.yaml"

destroy-universe:
	./scripts/destroy.sh

destroy-gitops:
	./scripts/utils/validate-kustomize.sh
	kubectl -n argocd delete -f "$(ROOT_DIR)/platform/argocd/bootstrap/dev-root-application.yaml" >/dev/null 2>&1 || true
	kustomize build --enable-helm --enable-alpha-plugins --enable-exec "$(ROOT_DIR)/clusters/single/dev" | kubectl delete -f - >/dev/null || true

destroy-cluster: destroy-gitops
	cd scripts/pulumi/cluster && pulumi destroy -y

destroy-foundation:
	cd scripts/pulumi/foundation && pulumi destroy -y
