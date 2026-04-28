#!/usr/bin/env bash
set -euo pipefail

NS_CM="cert-manager"
NS_CA="step-ca"
ISSUER="step-ca-int-acme"

log() { echo "[fix-step-ca] $*"; }

# ---- waits ----
wait_for() {
	log "Waiting for cert-manager + webhook..."
	kubectl wait --for=condition=Available deployment/cert-manager -n "$NS_CM" --timeout=300s

	# wait until webhook deployment exists, then ready
	until kubectl get deploy cert-manager-webhook -n "$NS_CM" >/dev/null 2>&1; do sleep 2; done
	kubectl wait --for=condition=Available deployment/cert-manager-webhook -n "$NS_CM" --timeout=300s

	log "Waiting for step-ca..."
	# adjust label if needed
	until kubectl get pods -n "$NS_CA" -l app.kubernetes.io/name=step-ca -o name >/dev/null 2>&1; do sleep 2; done
	kubectl wait --for=condition=Ready pod -n "$NS_CA" -l app.kubernetes.io/name=step-ca --timeout=300s

	log "Waiting for ClusterIssuer..."
	until kubectl get clusterissuer "$ISSUER" >/dev/null 2>&1; do sleep 2; done
}

# ---- extract CA (2nd cert in chain) ----
get_ca_bundle() {
	kubectl exec -n step-ca deploy/step-ca -- \
		cat /home/step/certs/root_ca.crt |
		base64 |
		tr -d '\n'
}

# ---- patch if needed ----
patch_issuer() {
	local ca="$1"
	local current
	current="$(kubectl get clusterissuer "$ISSUER" -o jsonpath='{.spec.acme.caBundle}' 2>/dev/null || true)"

	if [[ "$current" == "$ca" ]]; then
		log "CA bundle already up to date"
		return 0
	fi

	log "Patching ClusterIssuer caBundle"
	kubectl patch clusterissuer "$ISSUER" \
		--type=merge \
		-p "{\"spec\":{\"acme\":{\"caBundle\":\"${ca}\"}}}"

	log "Resetting ACME account to re-register"
	kubectl delete secret step-ca-int-acme-account-key -n "$NS_CM" --ignore-not-found
}

main() {
	wait_for
	ca="$(get_ca_bundle)"
	if [[ -z "$ca" ]]; then
		log "Failed to extract CA bundle"
		exit 1
	fi
	patch_issuer "$ca"
	log "Done"
}

main "$@"
