#!/usr/bin/env bash
set -euo pipefail

ssh-add 2>/dev/null || true

########################################
# Config
########################################

export ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SCRIPTS_DIR="$ROOT_DIR/scripts"
source "$SCRIPTS_DIR/lib/paths.sh"
source "$SCRIPTS_DIR/lib/civo-loadbalancers.sh"

source "$ROOT_DIR/.env"

CLUSTER_DEPLOYMENT_ROOT="$ROOT_DIR/clusters/single/$ENVIRONMENT"
if [[ "$CLOUD" == "civo" ]]; then
	CLUSTER_DEPLOYMENT_ROOT="$ROOT_DIR/clusters/single/civo/$ENVIRONMENT"
fi

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

discover_civo_private_ingress_ip() {
	local private_ip="" public_ip=""

	require_cmd curl
	require_cmd jq
	require_cmd python3
	log "Discovering the Civo private ingress address..."
	private_ip=$(civo_private_service_ip ingress-nginx ingress-nginx-private-controller) ||
		fail "Could not discover the private ingress address"
	for _ in $(seq 1 60); do
		public_ip=$(kubectl get service ingress-nginx-public-controller \
			-n ingress-nginx \
			-o jsonpath='{.status.loadBalancer.ingress[0].ip}' \
			2>/dev/null || true)
		[[ -n "$public_ip" ]] && break
		sleep 5
	done
	[[ -n "$public_ip" ]] || fail "Civo did not assign a public ingress address"

	export CIVO_PRIVATE_LB_IP="$private_ip"
	export CIVO_PUBLIC_LB_IP="$public_ip"
	log "Private ingress address: $CIVO_PRIVATE_LB_IP"
	log "Public ingress address: $CIVO_PUBLIC_LB_IP"
}

kustomize_build() {
	if [[ -n "${SOPS_AGE_KEY:-}" && -r "$SOPS_AGE_KEY" ]]; then
		SOPS_AGE_KEY_FILE="$SOPS_AGE_KEY" env -u SOPS_AGE_KEY \
			kustomize build \
			--enable-helm \
			--enable-alpha-plugins \
			--enable-exec \
			"$@"
	else
		kustomize build \
			--enable-helm \
			--enable-alpha-plugins \
			--enable-exec \
			"$@"
	fi
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
	"$SCRIPTS_DIR"/generate-env.sh || fail "Could not refresh cluster outputs"
	set -a
	source "$ROOT_DIR/.env.pulumi.generated"
	set +a
	"$SCRIPTS_DIR"/bootstrap-secrets.sh || fail "Could not bootstrap kube secrets"
	log "✅ Cluster manifestation complete."
}

setup_wireguard() {
	if [[ "${WIREGUARD_ENABLED:-}" != "true" ]]; then
		log "🌀 Wireguard disabled."
		return 0
	fi

	log "🔑 Binding keys to unseen gates..."
	if [[ "$CLOUD" == "civo" ]]; then
		"$SCRIPTS_DIR"/wireguard/setup-civo.sh
	else
		"$SCRIPTS_DIR"/wireguard/setup.sh
	fi
	log "⚡ The conduit holds. You may pass."

	pause_for_operator \
		"Enable the local DNS AWS forwarder now, then press Enter to continue..."
}

replace_civo_placeholder() {
	local rendered="$1" placeholder="$2" variable="$3"
	local value="${!variable:-}"
	if grep -q "$placeholder" "$rendered"; then
		[[ -n "$value" ]] || fail "Missing $variable required by $rendered"
		# Escape replacement metacharacters; CIDRs can contain slashes.
		value="${value//\\/\\\\}"
		value="${value//&/\\&}"
		value="${value//|/\\|}"
		sed -i "s|$placeholder|$value|g" "$rendered"
	fi
}

render_overlay() {
	local overlay="$1"
	local label="$2"

	local rendered="${label}.yaml"

	render_checked \
		"$overlay" \
		"$rendered" \
		"$label"

	if [[ "$CLOUD" == "civo" ]]; then
		# Require only settings actually referenced by this deployment stage.
		replace_civo_placeholder "$rendered" WIREGUARD_PRIVATE_IP_PLACEHOLDER WIREGUARD_PRIVATE_IP
		replace_civo_placeholder "$rendered" INT_DNS_HOST_PLACEHOLDER INT_DNS_HOST
		replace_civo_placeholder "$rendered" INTERNAL_DOMAIN_PLACEHOLDER INTERNAL_DOMAIN
		replace_civo_placeholder "$rendered" EXTERNAL_DOMAIN_PLACEHOLDER EXTERNAL_DOMAIN
		replace_civo_placeholder "$rendered" ENVIRONMENT_PLACEHOLDER ENVIRONMENT
		replace_civo_placeholder "$rendered" WIREGUARD_LOCAL_CIDR_PLACEHOLDER WIREGUARD__LOCAL_CIDRS
		replace_civo_placeholder "$rendered" CIVO_PRIVATE_LB_FIREWALL_ID_PLACEHOLDER PRIVATE_LB_FIREWALL_ID
		if [[ -n "${CIVO_PRIVATE_LB_IP:-}" ]]; then
			sed -i "s/CIVO_PRIVATE_LB_IP_PLACEHOLDER/${CIVO_PRIVATE_LB_IP}/g" "$rendered"
		fi
		# Keep service DNS disabled until all three private addresses are known.
		sed -i "s/CIVO_SERVICE_DNS_CONTROLLER_PLACEHOLDER/${CIVO_SERVICE_DNS_CONTROLLER:-awaiting-private-ip}/g" "$rendered"
		sed -i "s/CIVO_AMQP_PRIVATE_IP_PLACEHOLDER/${CIVO_AMQP_PRIVATE_IP:-pending.invalid}/g" "$rendered"
		sed -i "s/CIVO_MONGO_PRIVATE_IP_PLACEHOLDER/${CIVO_MONGO_PRIVATE_IP:-pending.invalid}/g" "$rendered"
		sed -i "s/CIVO_DB_PRIVATE_IP_PLACEHOLDER/${CIVO_DB_PRIVATE_IP:-pending.invalid}/g" "$rendered"
		if [[ -n "${CIVO_PUBLIC_LB_IP:-}" ]]; then
			sed -i "s/CIVO_PUBLIC_LB_IP_PLACEHOLDER/${CIVO_PUBLIC_LB_IP}/g" "$rendered"
		fi
	fi

	if grep -q '[A-Z][A-Z_]*_PLACEHOLDER' "$rendered"; then
		fail "$label contains unresolved configuration placeholders"
	fi

	apply_rendered "$rendered" "$label"
}

deploy_platform_services() {
	if [[ "$CLOUD" == "civo" ]]; then
		# Provision first; do not let ExternalDNS publish public Service status IPs.
		export CIVO_SERVICE_DNS_CONTROLLER=awaiting-private-ip
		unset CIVO_AMQP_PRIVATE_IP CIVO_MONGO_PRIVATE_IP CIVO_DB_PRIVATE_IP
	fi
	render_overlay "$CLUSTER_DEPLOYMENT_ROOT/40-platform-services" "platform-services"
	if [[ "$CLOUD" == "civo" ]]; then
		log "Discovering private addresses for RabbitMQ, MongoDB, and PostgreSQL..."
		CIVO_AMQP_PRIVATE_IP=$(civo_private_service_ip rabbitmq rabbitmq) || fail "RabbitMQ private address discovery failed"
		CIVO_MONGO_PRIVATE_IP=$(civo_private_service_ip forge-mongo forge-mongo-lb) || fail "MongoDB private address discovery failed"
		CIVO_DB_PRIVATE_IP=$(civo_private_service_ip forge-db forge-db-dev-lb) || fail "PostgreSQL private address discovery failed"
		export CIVO_AMQP_PRIVATE_IP CIVO_MONGO_PRIVATE_IP CIVO_DB_PRIVATE_IP
		export CIVO_SERVICE_DNS_CONTROLLER=dns-controller
		# Re-render the owning RabbitMQ/CNPG resources too, so operators retain targets.
		render_overlay "$CLUSTER_DEPLOYMENT_ROOT/40-platform-services" "platform-services"
		log "Private DNS targets: AMQP=$CIVO_AMQP_PRIVATE_IP MongoDB=$CIVO_MONGO_PRIVATE_IP PostgreSQL=$CIVO_DB_PRIVATE_IP S3=$CIVO_PRIVATE_LB_IP"
	fi
}

deploy_platform_bootstrap() {
	log "Deploying platform bootstrap substrate"

	require_cmd python3
	require_cmd kustomize
	require_cmd kubectl

	kubectl get ns argocd >/dev/null 2>&1 || kubectl create ns argocd
	kubectl get ns external-dns >/dev/null 2>&1 || kubectl create ns external-dns
	kubectl get ns cert-manager >/dev/null 2>&1 || kubectl create ns cert-manager
	if [[ "$CLOUD" != "civo" ]]; then
		kubectl get ns metallb-system >/dev/null 2>&1 || kubectl create ns metallb-system
	fi
	kubectl get ns step-ca >/dev/null 2>&1 || kubectl create ns step-ca

	########################################
	# Phase 1 — Controllers / CRDs
	########################################

	render_overlay \
		"$CLUSTER_DEPLOYMENT_ROOT/10-platform-core" \
		"platform-core"

	if [[ "$CLOUD" == "civo" ]]; then
		discover_civo_private_ingress_ip
	fi

	if [[ "$CLOUD" != "civo" ]]; then
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
	fi

	# give cluster a second to settle
	sleep 2

	########################################
	# Phase 2 — Configuration
	########################################

	render_overlay \
		"$CLUSTER_DEPLOYMENT_ROOT/20-platform-config" \
		"platform-config"

	########################################
	# Phase 3 - Operators/CRDs
	########################################

	render_overlay \
		"$CLUSTER_DEPLOYMENT_ROOT/30-platform-operators" \
		"platform-operators"

	log "Waiting for operator CRDs..."

	kubectl wait \
		--for=condition=Established \
		crd/keycloaks.k8s.keycloak.org \
		crd/rabbitmqclusters.rabbitmq.com \
		crd/clusters.postgresql.cnpg.io \
		crd/tenants.minio.min.io \
		crd/mongodbcommunity.mongodbcommunity.mongodb.com \
		--timeout=120s ||
		fail "Operator CRDs failed"

	log "Waiting for CNPG controller manager..."

	kubectl wait \
		--for=condition=Available \
		deployment/cnpg-cloudnative-pg \
		-n cnpg-system \
		--timeout=120s

	########################################
	# Phase 4 - Platform services
	########################################

	deploy_platform_services
}

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
	if [[ "$CLOUD" == "civo" ]]; then
		deploy_cluster
		setup_wireguard
	else
		setup_wireguard
		deploy_cluster
	fi
	deploy_platform_bootstrap
	bootstrap_step_ca_trust
	verify

	log "Forge is online 🔥"
}

case "${1:-}" in
	--platform-services)
		# Reconcile an existing cluster without rerunning Pulumi or bootstrap.
		[[ -r "$ROOT_DIR/.env.pulumi.generated" ]] || fail "Missing .env.pulumi.generated; refresh cluster outputs first"
		set -a
		source "$ROOT_DIR/.env.pulumi.generated"
		set +a
		cd "$CLUSTER_DIR" || fail "Missing cluster dir"
		if [[ "$CLOUD" == "civo" ]]; then
			discover_civo_private_ingress_ip
		fi
		deploy_platform_services
		;;
	"") main ;;
	*) fail "Usage: $0 [--platform-services]" ;;
esac
