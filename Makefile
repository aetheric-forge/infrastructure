.PHONY: configure foundation pulumi wireguard gitops clean

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
	kubectl -n argocd-dev apply -f platform/argocd/bootstrap/dev-root-application.yaml

all: foundation wireguard cluster gitops

clean:
	kustomize build --enable-helm --enable-alpha-plugins clusters/single/dev | kubectl delete -f - --ignore-not-found --timeout=5s || true
	(cd scripts/pulumi/cluster && pulumi destroy -y)
	(cd scripts/pulumi/foundation && pulumi destroy -y)
