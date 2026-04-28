#!/usr/bin/env bash
set -euo pipefail

pwd
source ../../../.env
source ../../../.env.pulumi.generated

NAMESPACE="argocd"

: "${SOPS_AGE_KEY:?must be set}"
: "${SSH_REPO_KEY:?must be set}"
: "${GIT_REPO_URL:?must be set}"

echo "[Forge] Waiting for cluster..."
for i in $(seq 1 60); do
	if kubectl get nodes >/dev/null 2>&1; then
		break
	fi
	sleep 5
done

echo "[Forge] Creating argocd namespace"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

echo "[Forge] Applying sops-age secret"
kubectl create secret generic sops-age \
	-n "$NAMESPACE" \
	--from-file=keys.txt="$SOPS_AGE_KEY" \
	--dry-run=client -o yaml | kubectl apply -f -

echo "[Forge] Applying repo-git-ssh secret"

kubectl create secret generic repo-git-ssh \
	-n argocd \
	--from-file=sshPrivateKey="$SSH_REPO_KEY" \
	--dry-run=client -o yaml |
	kubectl apply -f -

kubectl patch secret repo-git-ssh -n argocd --type merge -p "
{
  \"metadata\": {
    \"labels\": {
      \"argocd.argoproj.io/secret-type\": \"repository\"
    }
  },
  \"stringData\": {
    \"type\": \"git\",
    \"url\": \"${GIT_REPO_URL}\"
  }
}
"

echo "[Forge] Installing kube CA bundle in cert-manager"

kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -

kubectl get configmap kube-root-ca.crt -n kube-system -o jsonpath='{.data.ca\.crt}' |
	kubectl create secret generic kube-ca \
		-n cert-manager \
		--from-file=ca.crt=/dev/stdin \
		--dry-run=client -o yaml |
	kubectl apply -f -

echo "[Forge] Done"
