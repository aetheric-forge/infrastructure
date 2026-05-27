#!/usr/bin/env bash
set -euo pipefail

export ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/paths.sh"

source "$ROOT_DIR/.env"
source "$ROOT_DIR/.env.pulumi.generated"

########################################
# Logging
########################################

log() {
	echo "[destroy] $*"
}

warn() {
	echo "[destroy][warn] $*" >&2
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
# Kube API detection (fast TCP probe)
########################################

check_kube_api() {
	timeout 20 kubectl get ns kube-system >/dev/null 2>&1
	return $?
}

########################################
# GitOps unwind (safe)
########################################

unwind_gitops() {
	if check_kube_api; then
		log "Cluster reachable → unwinding GitOps resources..."
		kubectl delete -n argocd -f "$ROOT_DIR/clusters/single/dev/gitops/dev-root-application.yaml" --ignore-not-found 2>/dev/null || true
		log "🧹 Purging DNS01 artifacts..."
		kubectl delete cert,certificaterequest --all -A || true
		sleep 5

		kustomize build --enable-helm --enable-alpha-plugins --enable-exec "$ROOT_DIR/clusters/single/dev/bootstrap" | kubectl delete \
			--ignore-not-found \
			--grace-period=0 \
			--force \
			--wait=false \
			--request-timeout='5s' \
			-f - >/dev/null 2>&1 || true
	else
		log "Cluster API unreachable → skipping GitOps unwind"
	fi
}

########################################
# Teardown steps (plug in your real commands)
########################################

teardown_cluster() {
	log "Tearing down cluster..."
	cd "$CLUSTER_DIR" && pulumi destroy -y || true
	cd "$ROOT_DIR"
}

teardown_foundation() {
	pause_for_operator "[destroy] Disable the local DNS AWS forwarder before WireGuard is destroyed, then press Enter to continue..."
	log "Tearing down foundation..."

	if [ "$CLOUD" == "aws" ]; then
		ASSOC_ID="$(
			aws ec2 describe-addresses \
				--region "$AWS_REGION" \
				--filters "Name=public-ip,Values=${WIREGUARD_PUBLIC_IP}" \
				--query 'Addresses[0].AssociationId' \
				--output text
		)"

		if [[ "$ASSOC_ID" != "None" && "$ASSOC_ID" != "null" && -n "$ASSOC_ID" ]]; then
			aws ec2 disassociate-address \
				--region "$AWS_REGION" \
				--association-id "$ASSOC_ID"
		fi
	fi
	cd "$FOUNDATION_DIR" && pulumi destroy -y || true
	cd "$ROOT_DIR"
	pause_for_operator "[destroy] WireGuard foundation resources are destroyed. Confirm local DNS is stable, then press Enter to finish..."
}

########################################
# Main sequence
########################################

main() {
	log "Starting destroy sequence"

	# Step 1 — unwind GitOps while cluster still exists
	unwind_gitops

	# Step 2 — kill cluster
	teardown_cluster

	# Step 4 — perform required DNS mutation (critical ordering)
	#update_resolv

	# Step 5 — tear down base infrastructure
	teardown_foundation

	log "Destroy complete"
}

main "$@"
