#!/usr/bin/env bash
set -euo pipefail

source .env

########################################
# Config
########################################

DNS_SERVER="${DNS_SERVER:-10.0.0.2}"
BACKUP_FILE="../../../.resolv.conf.backup"
RESOLV_CONF="/etc/resolv.conf"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SCRIPTS_DIR="$ROOT_DIR/scripts"
FOUNDATION_DIR="$ROOT_DIR/scripts/pulumi/foundation"
CLUSTER_DIR="$ROOT_DIR/scripts/pulumi/cluster"

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

########################################
# Stage 0 — DNS Override
########################################

dns_apply() {
	log "Applying DNS override → $DNS_SERVER"

	if [ ! -f "$BACKUP_FILE" ]; then
		cp "$RESOLV_CONF" "$BACKUP_FILE"
		log "Backed up resolv.conf → $BACKUP_FILE"
	else
		log "Backup already exists"
	fi

	sudo tee "$RESOLV_CONF" >/dev/null <<EOF
# Managed by Forge create.sh
search $INTERNAL_DOMAIN
nameserver $DNS_SERVER
options edns0
EOF
}

########################################
# Stage 1 — Foundation
########################################

deploy_foundation() {
	log "Deploying foundation (Pulumi)"

	cd "$FOUNDATION_DIR" || fail "Missing foundation dir"

	"$SCRIPTS_DIR"/pulumi/pulumi-up.sh || fail "Foundation deployment failed"
	"$SCRIPTS_DIR"/generate-env.sh || fail "Could not update .env"
	"$SCRIPTS_DIR"/generate-values.sh || fail "Could not generate external-dns values.yaml"
}

########################################
# Stage 2 — Cluster
########################################

deploy_cluster() {
	log "Deploying cluster (Pulumi)"

	cd "$CLUSTER_DIR" || fail "Missing cluster dir"

	"$SCRIPTS_DIR"/pulumi/pulumi-up.sh || fail "Cluster deployment failed"
	"$SCRIPTS_DIR"/merge-kubeconfig.sh || fail "Could not update ~/.kube/config"
	"$SCRIPTS_DIR"/bootstrap-secrets.sh || fail "Could not bootstrap kube secrets"
}

setup_wireguard() {
	log "Bringing up WireGuard tunnel to AWS"

	"$SCRIPTS_DIR"/wireguard/setup.sh
}

########################################
# Stage 3 — GitOps (ArgoCD)
########################################

deploy_gitops() {
	log "Deploying GitOps (ArgoCD via Kustomize)"

	kubectl get ns argocd >/dev/null 2>&1 || kubectl create ns argocd
	kubectl get ns external-dns >/dev/null 2>&1 || kubectl create ns external-dns

	kustomize build --enable-helm --enable-alpha-plugins ../../../clusters/single/dev | kubectl apply -f - || fail "GitOps deployment failed"
	kubectl -n argocd apply -f ../../../platform/argocd/bootstrap/dev-root-application.yaml
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

patch_step_ca_bundle() {
	log "Patching ClusterIssuer with step-ca CA bundle"

	# wait for issuer + deps to actually exist
	kubectl wait --for=condition=Available deployment -n cert-manager cert-manager --timeout=300s
	kubectl wait --for=condition=Available deployment -n cert-manager cert-manager-webhook --timeout=300s
	kubectl wait --for=condition=Ready pod -n step-ca -l app=step-ca --timeout=300s
	kubectl wait --for=jsonpath='{.metadata.name}'=step-ca-int-acme clusterissuer/step-ca-int-acme --timeout=120s || true

	# extract the correct CA (2nd cert in chain)
	CA_BUNDLE=$(kubectl exec -n step-ca deploy/step-ca -- \
		sh -c "echo | openssl s_client -connect 127.0.0.1:9000 2>/dev/null \
        | awk 'BEGIN{c=0}/BEGIN CERT/{c++} c==2{print}'" |
		base64 -w0)

	# patch only if needed (idempotent)
	CURRENT=$(kubectl get clusterissuer step-ca-int-acme -o jsonpath='{.spec.acme.caBundle}' 2>/dev/null || echo "")
	if [ "$CURRENT" != "$CA_BUNDLE" ]; then
		kubectl patch clusterissuer step-ca-int-acme \
			--type=merge \
			-p "{\"spec\":{\"acme\":{\"caBundle\":\"${CA_BUNDLE}\"}}}"
	fi

	# reset ACME once so it re-registers with the new trust
	kubectl delete secret step-ca-int-acme-account-key -n cert-manager --ignore-not-found

	log "CA bundle patched"
}

########################################
# Main
########################################

main() {
	log "Forge bootstrap starting"

	deploy_foundation
	setup_wireguard
	dns_apply
	deploy_cluster
	deploy_gitops
	patch_step_ca_bundle
	verify

	log "Forge is online 🔥"
}

main "$@"
