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

echo "[Forge] Installing step-ca CA bundle in cert-manager"

kubectl exec -n step-ca deploy/step-ca -- \
	sh -c "echo | openssl s_client -connect 127.0.0.1:9000 2>/dev/null \
  | awk 'BEGIN{c=0}/BEGIN CERT/{c++} c==2{print}'" |
	base64 -w0 |
	xargs -I {} kubectl patch clusterissuer step-ca-int-acme \
		--type='merge' \
		-p "{\"spec\":{\"acme\":{\"caBundle\":\"{}\"}}}"

kubectl -n cert-manager rollout restart deployment cert-manager

echo "[Forge] Done"
