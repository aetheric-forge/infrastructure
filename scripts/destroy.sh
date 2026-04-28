#!/usr/bin/env bash
set -euo pipefail

source .env
source .env.pulumi.generated

########################################
# Logging
########################################

log() {
	echo "[destroy] $*"
}

warn() {
	echo "[destroy][warn] $*" >&2
}

########################################
# Kube API detection (fast TCP probe)
########################################

check_kube_api() {
	timeout 20 kubectl get ns kube-system >/dev/null 2>&1
	return $?
}

########################################
# DNS update (your ritual)
########################################

update_resolv() {
	log "Updating resolv.conf..."

	# Example — replace with your real logic
	if [ -f .resolv.conf.backup ]; then
		sudo mv -f .resolv.conf.backup /etc/resolv.conf
	else
		sudo tee /etc/resolv.conf >/dev/null <<EOF
# Managed by Forge create.sh
search $INTERNAL_DOMAIN
nameserver 10.0.0.2
options edns0
EOF
	fi
	echo "[✓] DNS restored"
}

########################################
# GitOps unwind (safe)
########################################

unwind_gitops() {
	if check_kube_api; then
		log "Cluster reachable → unwinding GitOps resources..."
		kubectl delete -n argocd -f platform/argocd/bootstrap/dev-root-application.yaml --ignore-not-found
		kustomize build --enable-helm --enable-alpha-plugins clusters/single/dev | kubectl delete \
			--ignore-not-found \
			--grace-period=0 \
			--force \
			--wait=false \
			--request-timeout='5s' \
			-f -
	else
		log "Cluster API unreachable → skipping GitOps unwind"
	fi
}

########################################
# Teardown steps (plug in your real commands)
########################################

teardown_cluster() {
	log "Tearing down cluster..."
	cd scripts/pulumi/cluster && pulumi destroy -y || true
	cd ../../..
}

teardown_foundation() {
	log "Tearing down foundation..."

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
	cd scripts/pulumi/foundation && pulumi destroy -y || true
	cd ../../..
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
	update_resolv

	# Step 5 — tear down base infrastructure
	teardown_foundation

	log "Destroy complete"
}

main "$@"
