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

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

kustomize_build() {
	kustomize build \
		--enable-helm \
		--enable-alpha-plugins \
		--enable-exec \
		"$@"
}

render_checked() {
	local overlay="$1"
	local output="$2"
	local label="$3"

	log "Rendering $label..."
	kustomize_build "$overlay" >"$output"

	test -s "$output" || fail "$label rendered empty"

	if [[ "$label" == "platform bootstrap" ]]; then
		grep -qi 'step-ca' "$output" || {
			echo
			echo "Rendered file kept at: $output"
			fail "platform bootstrap render does not contain step-ca"
		}
	fi
}

apply_rendered() {
	local rendered="$1"
	local label="$2"

	log "Applying $label..."
	kubectl apply --server-side -f "$rendered" || fail "$label apply failed"
}

wait_for_namespace() {
	local ns="$1"
	local timeout="${2:-180}"

	log "Waiting for namespace/$ns..."
	kubectl wait --for=jsonpath='{.metadata.name}'="$ns" "namespace/$ns" --timeout="${timeout}s" ||
		fail "namespace/$ns did not appear"
}

wait_for_deployment() {
	local ns="$1"
	local deploy="$2"
	local timeout="${3:-300}"

	log "Waiting for deployment/$deploy in namespace/$ns..."
	until kubectl get "deploy/$deploy" -n "$ns" >/dev/null 2>&1; do
		sleep 2
	done

	kubectl rollout status "deploy/$deploy" -n "$ns" --timeout="${timeout}s" ||
		fail "deployment/$deploy did not become ready"
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

render_overlay() {
	local overlay="$1"
	local label="$2"

	local rendered="${label}.yaml"

	render_checked \
		"$overlay" \
		"$rendered" \
		"$label"

	apply_rendered "$rendered" "$label"
}

########################################
# Stage 3 — Bootstrap platform resources
########################################

deploy_platform_bootstrap() {
	log "Deploying platform bootstrap substrate"

	require_cmd python3
	require_cmd kustomize
	require_cmd kubectl

	kubectl get ns argocd >/dev/null 2>&1 || kubectl create ns argocd
	kubectl get ns external-dns >/dev/null 2>&1 || kubectl create ns external-dns
	kubectl get ns cert-manager >/dev/null 2>&1 || kubectl create ns cert-manager
	kubectl get ns metallb-system >/dev/null 2>&1 || kubectl create ns metallb-system
	kubectl get ns step-ca >/dev/null 2>&1 || kubectl create ns step-ca

	########################################
	# Phase 1 — Controllers / CRDs
	########################################

	render_overlay \
		"$ROOT_DIR/clusters/single/$ENVIRONMENT/bootstrap/10-platform-core" \
		"platform-core"

	log "Waiting for metallb CRDs..."
	for crd in ipaddresspools.metallb.io l2advertisements.metallb.io; do
		until kubectl get crd "$crd" >/dev/null 2>&1; do
			sleep 2
		done
	done

	kubectl wait \
		--for=condition=Established \
		crd/ipaddresspools.metallb.io \
		crd/l2advertisements.metallb.io \
		--timeout=120s ||
		fail "metallb CRDs failed"

	log "Waiting for metallb controller..."
	kubectl rollout status \
		deployment/metallb-controller \
		-n metallb-system \
		--timeout=120s ||
		fail "metallb controller failed"

	# give cluster a second to settle
	sleep 2

	########################################
	# Phase 2 — Configuration
	########################################

	render_overlay \
		"$ROOT_DIR/clusters/single/$ENVIRONMENT/bootstrap/20-platform-config" \
		"platform-config"
}
########################################
# Stage 4 — Step CA trust
########################################

bootstrap_step_ca_trust() {
	log "[Forge] Bootstrapping Step CA trust"

	wait_for_namespace step-ca 180
	wait_for_deployment step-ca step-ca 300

	local pod
	pod="$(
		kubectl get pod -n step-ca \
			-l app.kubernetes.io/name=step-ca \
			-o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
	)"

	if [[ -z "$pod" ]]; then
		pod="$(
			kubectl get pod -n step-ca \
				-o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
		)"
	fi

	[[ -n "$pod" ]] || fail "Could not find a step-ca pod"

	kubectl exec -n step-ca "$pod" -- \
		cat /home/step/certs/root_ca.crt \
		>/tmp/root_ca.crt || fail "Failed to extract root CA"

	test -s /tmp/root_ca.crt || fail "root_ca.crt is empty"

	kubectl create secret generic step-ca-root-ca \
		-n cert-manager \
		--from-file=ca.crt=/tmp/root_ca.crt \
		--dry-run=client -o yaml | kubectl apply -f -

	local ca_bundle
	ca_bundle="$(base64 </tmp/root_ca.crt | tr -d '\n')"

	kubectl patch clusterissuer step-ca-int-acme \
		--type merge \
		-p "{
			\"spec\": {
				\"acme\": {
					\"caBundle\": \"${ca_bundle}\"
				}
			}
		}" || fail "Could not patch step-ca-int-acme ClusterIssuer"

	rm -f /tmp/root_ca.crt
}

########################################
# Stage 5 — GitOps app declarations
########################################

deploy_gitops_apps() {
	log "Handing control to GitOps app declarations"

	render_overlay \
		"$ROOT_DIR/clusters/single/$ENVIRONMENT/gitops" \
		"gitops"
}

########################################
# Stage 6 — Verification
########################################

verify() {
	log "Running basic verification"

	kubectl get ns argocd >/dev/null 2>&1 || fail "argocd namespace missing"
	kubectl get ns external-dns >/dev/null 2>&1 || fail "external-dns namespace missing"
	kubectl get ns cert-manager >/dev/null 2>&1 || fail "cert-manager namespace missing"
	kubectl get ns step-ca >/dev/null 2>&1 || fail "step-ca namespace missing"

	kubectl get deploy -n step-ca step-ca >/dev/null 2>&1 ||
		fail "step-ca deployment missing"

	kubectl get secret -n argocd sops-age >/dev/null 2>&1 ||
		fail "sops-age secret missing"

	kubectl get secret -n argocd repo-git-ssh >/dev/null 2>&1 ||
		fail "repo-git-ssh secret missing"

	log "Verification passed"
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
	deploy_platform_bootstrap
	deploy_gitops_apps
	bootstrap_step_ca_trust
	verify

	log "Forge is online 🔥"
}

main "$@"
