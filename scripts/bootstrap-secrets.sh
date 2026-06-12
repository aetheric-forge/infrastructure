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
	--from-literal=apiToken="$CF_API_KEY" \
	--dry-run=client -o yaml |
	kubectl apply -f -

kubectl create ns cert-manager --dry-run=client -o yaml | kubectl apply -f -

kubectl -n cert-manager create secret generic cloudflare-api-token \
	--from-literal=apiToken="$CF_API_KEY" \
	--dry-run=client -o yaml |
	kubectl apply -f -

echo "[Forge] Creating secret external-dns-internal-tsig"

kubectl -n external-dns create secret generic external-dns-internal-tsig \
	--from-literal=tsig-secret="$EXT_DNS_TSIG_KEY" \
	--dry-run=client -o yaml |
	kubectl apply -f -

echo "[Forge] Creating secret cert-manager-internal-tsig"

kubectl create ns cert-manager --dry-run=client -o yaml | kubectl apply -f -

kubectl -n cert-manager create secret generic cert-manager-tsig \
	--from-literal=tsig-secret="$CERT_MGR_TSIG_KEY" \
	--dry-run=client -o yaml |
	kubectl apply -f -

echo "[Forge] Creating secret root-ca-secret"

kubectl create ns step-ca --dry-run=client -o yaml | kubectl apply -f -

if [[ -n "$STEP_CA__CERT_FILE" ]]; then
	CERT_FILE=$STEP_CA__CERT_FILE
	KEY_FILE=$STEP_CA__KEY_FILE
else

	KEY_FILE=$ROOT_DIR/platform/step-ca/certs/dev/root_ca.key
	if [[ ! -f $KEY_FILE ]]; then
		openssl genpkey -algorithm ED25519 -out $KEY_FILE
	fi

	CERT_FILE=$ROOT_DIR/platform/step-ca/certs/dev/root_ca.crt
	if [[ ! -f $CERT_FILE ]]; then
		openssl req -x509 -new \
			-key $KEY_FILE \
			-out $CERT_FILE \
			-days 7300 \
			-subj "/CN=Aetheric Forge Root CA" \
			-addext "basicConstraints=critical,CA:true" \
			-addext "keyUsage=critical,keyCertSign,cRLSign"
	fi
fi

DIR=$ROOT_DIR/platform/step-ca/certs/$ENVIRONMENT
mkdir -p $DIR

SECRETS_FILE="$DIR/step-ca-root-ca.yaml"
ENCRYPTED_FILE="$DIR/step-ca-root-ca.enc.yaml"

cat >"$SECRETS_FILE" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: step-ca-root-ca
  namespace: step-ca
type: Opaque
stringData:
  root_ca.crt: |
$(sed 's/^/    /' "$CERT_FILE")
  root_ca.key: |
$(sed 's/^/    /' "$KEY_FILE")
EOF

cp $SECRETS_FILE $ENCRYPTED_FILE
sops --encrypt --in-place "$ENCRYPTED_FILE"

rm "$SECRETS_FILE"

echo "[Forge] Done"
