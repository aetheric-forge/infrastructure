#!/usr/bin/env bash
set -euo pipefail

source .env

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

get_kube_host_port() {
	local server host port

	server=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || true)

	if [[ -z "${server:-}" ]]; then
		return 1
	fi

	host=$(echo "$server" | sed -E 's#https?://([^:/]+).*#\1#')
	port=$(echo "$server" | sed -E 's#https?://[^:/]+:([0-9]+).*#\1#')

	port=${port:-443}

	echo "$host $port"
}

check_kube_api() {
	local host port

	if ! read -r host port < <(get_kube_host_port); then
		return 1
	fi

	timeout 2 bash -c "</dev/tcp/$host/$port" >/dev/null 2>&1
}

########################################
# DNS update (your ritual)
########################################

update_resolv() {
	log "Updating resolv.conf..."

	pwd
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

		# Replace path with your actual kustomize target
		kustomize build ./gitops |
			kubectl delete -f - --ignore-not-found=true ||
			warn "kubectl delete returned non-zero (continuing)"
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

	# disassociate EIPs because Pulumi doesn't properly do so before detaching the ENI
	aws ec2 describe-addresses \
		--query 'Addresses[?AssociationId!=null].AssociationId' \
		--output text |
		xargs -r -n1 aws ec2 disassociate-address --association-id || true

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
