#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/paths.sh"

source "$ROOT_DIR/.env"
source "$ROOT_DIR/.env.pulumi.generated"

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

echo "[Forge] Creating secret cloudflare-api-token"

kubectl create ns external-dns --dry-run=client -o yaml | kubectl apply -f -
kubectl -n external-dns create secret generic cloudflare-api-token \
	--from-literal=api-token="$CF_API_KEY" \
	--dry-run=client -o yaml |
	kubectl apply -f -

kubectl -n external-dns create secret generic external-dns-internal-tsig \
    --from-literal=tsig-secret="$TSIG_KEY" \
	--dry-run=client -o yaml |
	kubectl apply -f -

echo "[Forge] Done"
