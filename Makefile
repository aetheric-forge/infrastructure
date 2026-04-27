.PHONY: create

create:
	./scripts/create.sh

configure:
	./scripts/configure.sh

foundation:
	./scripts/pulumi-up.sh foundation
	./scripts/generate-env.sh
	./scripts/generate-values.sh

wireguard:
	./scripts/wireguard/setup.sh

cluster:
	./scripts/pulumi-up.sh cluster
	./scripts/merge-kubeconfig.sh

gitops:
	./scripts/utils/validate-kustomize.sh
	kubectl apply -f platform/external-dns/base/namespaces.yaml
	kustomize build --enable-helm --enable-alpha-plugins clusters/single/dev | kubectl apply -f -
	kubectl -n argocd apply -f platform/argocd/bootstrap/dev-root-application.yaml

destroy:
	./scripts/destroy.sh

