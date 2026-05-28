#!/usr/bin/env bash
set -euo pipefail

ssh-add 2>/dev/null || true

########################################
# Config
########################################

export ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SCRIPTS_DIR="$ROOT_DIR/scripts"
source "$SCRIPTS_DIR/lib/paths.sh"

source "$ROOT_DIR/.env"

NS_CM="cert-manager"
NS_CA="step-ca"

########################################
# Helpers
########################################

log() {
	echo -e "\n\033[1;34m[Forge]\033[0m $1"
}

fail() {
	echo -e "\n\033[1;31m[Error]\033[0m $1"
	exit 1
}

pause_for_operator() {
	local message="$1"

	if [[ -t 0 ]]; then
		read -rp "$message"
	else
		log "$message"
	fi
}

########################################
# Stage 1 — Foundation
########################################

deploy_foundation() {
	log "⚙️  Applying foundational laws..."
	cd "$FOUNDATION_DIR" || fail "Missing foundation dir"

	"$SCRIPTS_DIR"/pulumi/pulumi-up.sh || fail "Foundation deployment failed"
	"$SCRIPTS_DIR"/generate-env.sh || fail "Could not update .env"
	"$SCRIPTS_DIR"/generate-values.sh || fail "Could not generate external-dns values.yaml"
	echo "⚡ The foundation holds. All else may now rise."
}

########################################
# Stage 2 — Cluster
########################################

deploy_cluster() {
	log "🧱  Assembling nodes into a coherent reality..."
	cd "$CLUSTER_DIR" || fail "Missing cluster dir"

	"$SCRIPTS_DIR"/pulumi/pulumi-up.sh || fail "Cluster deployment failed"
	"$SCRIPTS_DIR"/merge-kubeconfig.sh || fail "Could not update ~/.kube/config"
	"$SCRIPTS_DIR"/bootstrap-secrets.sh || fail "Could not bootstrap kube secrets"
	log "✅ Cluster manifestation complete."
}

setup_wireguard() {
	if [[ "${WIREGUARD_ENABLED:-}" != "true" ]]; then
		log "🌀 Wireguard disabled."
		return 0
	fi

	log "🔑 Binding keys to unseen gates..."
	"$SCRIPTS_DIR"/wireguard/setup.sh
	log "⚡ The conduit holds. You may pass."

	pause_for_operator \
		"Enable the local DNS AWS forwarder now, then press Enter to continue..."
}

########################################
# Stage 3 — GitOps (ArgoCD)
########################################

deploy_gitops() {
	log "Deploying bootstrap substrate"

	kubectl get ns argocd >/dev/null 2>&1 || kubectl create ns argocd
	kubectl get ns external-dns >/dev/null 2>&1 || kubectl create ns external-dns
	kubectl get ns cert-manager >/dev/null 2>&1 || kubectl create ns cert-manager
	kubectl get ns metallb-system >/dev/null 2>&1 || kubectl create ns metallb-system

	kustomize build \
		--enable-helm \
		--enable-alpha-plugins \
		--enable-exec \
		"$ROOT_DIR/clusters/single/dev/bootstrap" \
		| kubectl apply -f - \
		|| fail "Bootstrap deployment failed"

	log "Waiting for metallb CRDs..."

	kubectl wait \
		--for=condition=Established \
		crd/ipaddresspools.metallb.io \
		crd/l2advertisements.metallb.io \
		--timeout=120s

	log "Waiting for cert-manager CRDs..."

	kubectl wait \
		--for=condition=Established \
		crd/certificates.cert-manager.io \
		--timeout=120s \
		|| fail "cert-manager CRDs failed"

	log "Waiting for cert-manager webhook..."

	kubectl rollout status \
		deployment/cert-manager-webhook \
		-n cert-manager \
		--timeout=120s \
		|| fail "cert-manager webhook failed"

	log "Waiting for metallb controller..."

	kubectl rollout status \
		deployment/metallb-controller \
		-n metallb-system \
		--timeout=120s \
		|| fail "metallb controller failed"

	log "Waiting for ArgoCD..."

	kubectl rollout status \
		deployment/argocd-server \
		-n argocd \
		--timeout=120s \
		|| fail "ArgoCD failed"

	log "Handing control to GitOps"

	kubectl apply \
		-f "$ROOT_DIR/apps/dev-root-application.yaml" \
		|| fail "GitOps root app failed"
}
########################################
# Stage 4 — Verification (light sanity)
########################################

verify() {
	log "Running basic verification"

	kubectl get ns argocd >/dev/null 2>&1 || fail "argocd namespace missing"
	kubectl get ns external-dns >/dev/null 2>&1 || fail "external-dns namespace missing"

	kubectl get secret -n argocd sops-age >/dev/null 2>&1 ||
		fail "sops-age secret missing"

	kubectl get secret -n argocd repo-git-ssh >/dev/null 2>&1 ||
		fail "repo-git-ssh secret missing"

	log "Verification passed"
}

bootstrap_step_ca_trust() {
	log "[Forge] Bootstrapping Step CA trust"

	log "Waiting for step-ca namespace..."
	until kubectl get namespace step-ca >/dev/null 2>&1; do
		sleep 2
	done

	log "Waiting for step-ca deployment..."
	kubectl rollout status deploy/step-ca \
	-n step-ca \
	--timeout=300s

	kubectl exec -n step-ca deploy/step-ca -- \
		cat /home/step/certs/root_ca.crt \
		> /tmp/root_ca.crt || {
			log "Failed to extract root CA"
			return 1
		}

		test -s /tmp/root_ca.crt || {
			log "root_ca.crt is empty"
			return 1
		}

	kubectl create secret generic step-ca-root-ca \
		-n cert-manager \
		--from-file=ca.crt=/tmp/root_ca.crt \
		--dry-run=client -o yaml | kubectl apply -f -

	CA_BUNDLE=$(base64 -w0 /tmp/root_ca.crt)

	kubectl patch clusterissuer step-ca-int-acme \
		--type merge \
		-p "{
			\"spec\": {
				\"acme\": {
					\"caBundle\": \"${CA_BUNDLE}\"
				}
			}
		}"

	rm -f /tmp/root_ca.crt
}

########################################
# Main
########################################

main() {
	log "✨ Let there be infrastructure."
	sleep 0.5
	echo "🌌 Spinning up the universe..."
	deploy_foundation
	setup_wireguard
	deploy_cluster
	deploy_gitops
	bootstrap_step_ca_trust
	verify

	log "Forge is online 🔥"
}

main "$@"
