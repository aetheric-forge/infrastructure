#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/paths.sh"

source "$ROOT_DIR/.env"
source "$ROOT_DIR/.env.pulumi.generated"

function create_sops_secret {
	local secret_name=$1
	local namespace=$2
	local secret=$3
	local out_file=$4

	if [[ -z "$secret_name" || -z "$namespace" || -z "$out_file" ]]; then
		echo "create_sops_secret: missing required arguments"
		return 1
	fi

	echo "[Forge] creating secret ${namespace}/${secret_name}..."

	kubectl create ns "$namespace" --dry-run=client -o yaml | kubectl apply -f -

	mkdir -p "$(dirname "$out_file")" >/dev/null 2>&1

	printf '%s' "$secret" >"$out_file"
	sops --encrypt --in-place "$out_file"
}

function render_velero_bsl {
	local cert_file=$1

	local ca_cert
	ca_cert=$(base64 -w0 <"$cert_file")

	cat <<EOF >"$ROOT_DIR/platform/core/velero/overlays/dev/backupstoragelocation.yaml"
apiVersion: velero.io/v1
kind: BackupStorageLocation
metadata:
  name: default
  namespace: velero

spec:
  default: true
  provider: aws

  objectStorage:
    bucket: velero
    caCert: $ca_cert

  credential:
    name: cloud-credentials
    key: cloud

  config:
    region: minio
    s3ForcePathStyle: "true"
    s3Url: https://s3-dev.int.aethericforge.ca

EOF
}

function secret_exists() {
	local name=$1
	local namespace=$2

	kubectl -n "$namespace" get secret "$name" >/dev/null 2>&1
}

: "${SOPS_AGE_KEY:?must be set}"
: "${SSH_REPO_KEY:?must be set}"
: "${GIT_REPO_URL:?must be set}"

echo "[Forge] Waiting for cluster..."
for _ in $(seq 1 60); do
	if kubectl get nodes >/dev/null 2>&1; then
		break
	fi
	sleep 5
done

echo "[Forge] Creating argocd namespace"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

echo "[Forge] Applying sops-age secret"
kubectl create secret generic sops-age \
	-n argocd \
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

if [[ -n "$STEP_CA__CERT_FILE" ]]; then
	CERT_FILE=$STEP_CA__CERT_FILE
	KEY_FILE=$STEP_CA__KEY_FILE
else

	KEY_FILE=$ROOT_DIR/platform/core/step-ca/certs/dev/root_ca.key
	if [[ ! -f $KEY_FILE ]]; then
		openssl genpkey \
			-algorithm EC \
			-pkeyopt ec_paramgen_curve:P-256 \
			-out $KEY_FILE
	fi

	CERT_FILE=$ROOT_DIR/platform/core/step-ca/certs/dev/root_ca.crt
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

DIR=$ROOT_DIR/platform/core/step-ca/certs/$ENVIRONMENT
ENCRYPTED_FILE="$DIR/step-ca-root-ca.enc.yaml"

if secret_exists "step-ca-root-ca" "step-ca"; then
	echo "step-ca-root-ca already exists in step-ca; skipping generation"
else
	SECRET=$(
		cat <<EOF
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
	)

	create_sops_secret "step-ca-root-ca" \
		"step-ca" \
		"$SECRET" \
		"$ENCRYPTED_FILE"
fi

DIR=$ROOT_DIR/platform/services/forge-db/secrets/$ENVIRONMENT
ENCRYPTED_FILE="$DIR/step-ca-root-ca.enc.yaml"

if secret_exists "step-ca-root-ca" "aetheric-forge"; then
	echo "step-ca-root-ca already exists in aetheric-forge; skipping generation"
else
	SECRET=$(
		cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: step-ca-root-ca
  namespace: aetheric-forge
type: Opaque
stringData:
  ca.crt: |
$(sed 's/^/    /' "$CERT_FILE")
EOF
	)

	create_sops_secret "step-ca-root-ca" \
		"aetheric-forge" \
		"$SECRET" \
		"$ENCRYPTED_FILE"
fi

DIR=$ROOT_DIR/platform/services/minio/secrets/$ENVIRONMENT
out_file="$DIR/minio-env-configuration.enc.yaml"

if secret_exists "minio-env-configuration" "minio"; then
	echo "minio-env-configuration already exists in minio; skipping credentials regeneration"
else
	root_user="minio-root-$(openssl rand -hex 8)"
	root_password="$(openssl rand -base64 48 | tr -d '\n')"
	SECRET=$(
		cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: minio-env-configuration  
  namespace: minio
type: Opaque
stringData:
  config.env: |
    export MINIO_ACCESS_KEY="${root_user}"
    export MINIO_SECRET_KEY="${root_password}"
EOF
	)

	create_sops_secret "minio-env-configuration" \
		"minio" \
		"$SECRET" \
		"$out_file"
fi

DIR="$ROOT_DIR/platform/core/velero/secrets/$ENVIRONMENT"
out_file="$DIR/cloud-credentials.enc.yaml"

if secret_exists "cloud-credentials" "velero"; then
	echo "cloud-credentials already exists in velero; skipping regeneration"
else
	access_key=$(openssl rand -base64 16 | tr -dc 'A-Za-z0-9' | head -c 16)
	secret_key=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)

	SECRET=$(
		cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: cloud-credentials
  namespace: velero
type: Opaque
stringData:
  cloud: |
    [default]
    aws_access_key_id=$access_key
    aws_secret_access_key=$secret_key
EOF
	)

	create_sops_secret "cloud-credentials" \
		"velero" \
		"$SECRET" \
		"$out_file"

fi

render_velero_bsl "$ROOT_DIR/platform/core/step-ca/certs/dev/root_ca.crt"

DIR="$ROOT_DIR/platform/services/forge-db/secrets/$ENVIRONMENT"
out_file="$DIR/forge-db-backup-s3.enc.yaml"

if secret_exists "forge-db-backup-s3" "aetheric-forge"; then
	echo "forge-db-backup-s3 already exists in aetheric-forge; skipping regeneration"
else
	access_key=$(openssl rand -base64 16 | tr -dc 'A-Za-z0-9' | head -c 16)
	secret_key=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)

	SECRET=$(
		cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: forge-db-backup-s3
  namespace: aetheric-forge
type: Opaque
stringData:
  access-key-id: $access_key
  secret-access-key: $secret_key
EOF
	)

	create_sops_secret "forge-db-backup-s3" \
		"aetheric-forge" \
		"$SECRET" \
		"$out_file"

fi

DIR="$ROOT_DIR/platform/services/forge-db/secrets/$ENVIRONMENT"
out_file="$DIR/forge-cnpg-superuser.enc.yaml"

root_pw=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)

SECRET=$(
	cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: forge-cnpg-superuser
  namespace: aetheric-forge
type: kubernetes.io/basic-auth
stringData:
  username: postgres
  password: $root_pw
EOF
)

if secret_exists "forge-cnpg-superuser" "aetheric-forge"; then
	echo "forge-db-root already exists in aetheric-forge; skipping regeneration"
else
	create_sops_secret "forge-cnpg-superuser" \
		"aetheric-forge" \
		"$SECRET" \
		"$out_file"
fi

DIR="$ROOT_DIR/platform/services/forge-db/secrets/$ENVIRONMENT"

pw=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)

SECRET=$(
	cat <<EOF
apiVersion: v1
kind: Secret
metadata:
name: keycloak-db
namespace: aetheric-forge
type: kubernetes.io/basic-auth
stringData:
  username: keycloak
  password: $pw
EOF
)

if secret_exists "keycloak-db" "aetheric-forge"; then
	echo "Skipping secret creation as keycloak-db already exists in aetheric-forge"
else
	create_sops_secret "keycloak-db" \
		"aetheric-forge" \
		"$SECRET" \
		"$DIR/keycloak-db.enc.yaml"
fi

if secret_exists "keycloak-db" "keycloak"; then
	echo "Skipping secret creation as keycloak-db already exists in aetheric-forge"
else
	create_sops_secret "keycloak-db" \
		"keycloak" \
		"$SECRET" \
		"$ROOT_DIR/platform/services/keycloak/secrets/$ENVIRONMENT/keycloak-db.enc.yaml"
fi

admin_pw=$(openssl rand -base64 16 | tr -dc 'A-Za-z0-9' | head -c 16)

SECRET=$(
	cat <<EOF
apiVersion: v1
kind: Secret
metadata:
name: keycloak-admin
namespace: keycloak
type: kubernetes.io/basic-auth
stringData:
  username: admin
  password: $admin_pw
EOF
)

if secret_exists "keycloak-admin" "keycloak"; then
	echo "Skipping secret creation as keycloak-admin already exists in keycloak"
else
	create_sops_secret "keycloak-admin" \
		"keycloak" \
		"$SECRET" \
		"$ROOT_DIR/platform/services/keycloak/secrets/$ENVIRONMENT/keycloak-admin.enc.yaml"
fi

echo "[Forge] Done"
