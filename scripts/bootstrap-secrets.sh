#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/paths.sh"

source "$ROOT_DIR/.env"
source "$ROOT_DIR/.env.pulumi.generated"

FORGE_DB_NAMESPACE="forge-db"
KEYCLOAK_NAMESPACE="keycloak-system"
MINIO_NAMESPACE="minio"
VELERO_NAMESPACE="velero"
ARGOCD_NAMESPACE="argocd"
STEP_CA_NAMESPACE="step-ca"

function require_env() {
	for name in "$@"; do
		: "${!name:?$name must be set}"
	done
}

function ensure_namespace() {
	local namespace=$1

	kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
}

function apply_literal_secret() {
	local namespace=$1
	local secret_name=$2
	shift 2

	echo "[Forge] applying live secret ${namespace}/${secret_name}..."
	ensure_namespace "$namespace"

	kubectl -n "$namespace" create secret generic "$secret_name" \
		"$@" \
		--dry-run=client -o yaml |
		kubectl apply -f -
}

function secret_exists() {
	local namespace=$1
	local secret_name=$2

	kubectl -n "$namespace" get secret "$secret_name" >/dev/null 2>&1
}

function encrypt_file() {
	local out_file=$1
	local content=$2

	mkdir -p "$(dirname "$out_file")"
	printf '%s\n' "$content" >"$out_file"
	sops --encrypt --in-place "$out_file"
}

function create_sops_secret() {
	local namespace=$1
	local secret_name=$2
	local out_file=$3
	local content=$4

	if secret_exists "$namespace" "$secret_name" && [[ -f "$out_file" ]]; then
		echo "[Forge] ${namespace}/${secret_name} already exists; skipping"
		return
	fi

	echo "[Forge] creating SOPS secret ${namespace}/${secret_name}..."
	ensure_namespace "$namespace"
	if [[ -f "$out_file" ]]; then
		# we assume that the current secret is populated with the contents of the existing file. delete if not true.
		return
	fi
	encrypt_file "$out_file" "$content"
}

function rand_alnum() {
	local length=$1

	openssl rand -hex "$length" | tr -d '\n' | cut -c 1-"$length"
}

function indent_file() {
	local file=$1

	sed 's/^/    /' "$file"
}

function opaque_secret() {
	local namespace=$1
	local name=$2
	local string_data=$3

	cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: $name
  namespace: $namespace
type: Opaque
stringData:
$string_data
EOF
}

function basic_auth_secret() {
	local namespace=$1
	local name=$2
	local username=$3
	local password=$4

	cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: $name
  namespace: $namespace
type: kubernetes.io/basic-auth
stringData:
  username: $username
  password: $password
EOF
}

function wait_for_cluster() {
	echo "[Forge] Waiting for cluster..."

	for _ in $(seq 1 60); do
		if kubectl get nodes >/dev/null 2>&1; then
			return
		fi

		sleep 5
	done

	echo "[Forge] cluster did not become reachable in time"
	return 1
}

function bootstrap_argocd_access() {
	ensure_namespace "$ARGOCD_NAMESPACE"

	apply_literal_secret "$ARGOCD_NAMESPACE" "sops-age" \
		--from-file=keys.txt="$SOPS_AGE_KEY"

	apply_literal_secret "$ARGOCD_NAMESPACE" "repo-git-ssh" \
		--from-file=sshPrivateKey="$SSH_REPO_KEY"

	kubectl patch secret repo-git-ssh -n "$ARGOCD_NAMESPACE" --type merge -p "
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
}

function bootstrap_dns_secrets() {
	apply_literal_secret "external-dns" "cloudflare-api-token" \
		--from-literal=apiToken="$CF_API_KEY"
	apply_literal_secret "cert-manager" "cloudflare-api-token" \
		--from-literal=apiToken="$CF_API_KEY"
	apply_literal_secret "external-dns" "external-dns-internal-tsig" \
		--from-literal=tsig-secret="$EXT_DNS_TSIG_KEY"
	apply_literal_secret "cert-manager" "cert-manager-tsig" \
		--from-literal=tsig-secret="$CERT_MGR_TSIG_KEY"
}

function ensure_step_ca_files() {
	if [[ -n "${STEP_CA__CERT_FILE:-}" ]]; then
		: "${STEP_CA__KEY_FILE:?STEP_CA__KEY_FILE must be set when STEP_CA__CERT_FILE is set}"
		CERT_FILE=$STEP_CA__CERT_FILE
		KEY_FILE=$STEP_CA__KEY_FILE
		return
	fi

	KEY_FILE="$ROOT_DIR/platform/core/step-ca/certs/dev/root_ca.key"
	CERT_FILE="$ROOT_DIR/platform/core/step-ca/certs/dev/root_ca.crt"

	mkdir -p "$(dirname "$KEY_FILE")"

	if [[ ! -f "$KEY_FILE" ]]; then
		openssl genpkey \
			-algorithm EC \
			-pkeyopt ec_paramgen_curve:P-256 \
			-out "$KEY_FILE"
	fi

	if [[ ! -f "$CERT_FILE" ]]; then
		openssl req -x509 -new \
			-key "$KEY_FILE" \
			-out "$CERT_FILE" \
			-days 7300 \
			-subj "/CN=Aetheric Forge Root CA" \
			-addext "basicConstraints=critical,CA:true" \
			-addext "keyUsage=critical,keyCertSign,cRLSign"
	fi
}

function root_ca_secret() {
	local crt
	local key

	crt=$(indent_file "$CERT_FILE")
	key=$(indent_file "$KEY_FILE")

	cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: step-ca-root-ca
  namespace: $STEP_CA_NAMESPACE
type: Opaque
stringData:
  root_ca.crt: |
$crt
  root_ca.key: |
$key
EOF
}

function ca_bundle_secret() {
	local namespace=$1
	local crt

	crt=$(indent_file "$CERT_FILE")

	cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: step-ca-root-ca
  namespace: $namespace
type: Opaque
stringData:
  ca.crt: |
$crt
EOF
}

function step_ca_secrets() {
	local namespace="step-ca"

	local provisioner_pwd="$(rand_alnum 48)"
	local pwd="$(rand_alnum 32)"

	cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: step-ca-secrets
  namespace: $namespace
type: Opaque
stringData:
  provisioner_password: "$provisioner_pwd"
  password: "$pwd"
EOF
}

function argocd_oidc_secret() {
	local namespace="argocd"
	local
}

function distribute_step_ca_certificates() {
	local root_dir="$ROOT_DIR/platform/core/step-ca/certs/$ENVIRONMENT"
	create_sops_secret "$STEP_CA_NAMESPACE" "step-ca-root-ca" \
		"$root_dir/step-ca-root-ca.enc.yaml" \
		"$(root_ca_secret)"

	create_sops_secret "$STEP_CA_NAMESPACE" "step-ca-secrets" \
		"$root_dir/step-ca-secrets.enc.yaml" \
		"$(step_ca_secrets)"

	local targets=(
		"argocd:$ROOT_DIR/platform/services/argocd/secrets/$ENVIRONMENT/step-ca-root-ca.enc.yaml"
		"$FORGE_DB_NAMESPACE:$ROOT_DIR/platform/services/forge-db/secrets/$ENVIRONMENT/step-ca-root-ca.enc.yaml"
		"$KEYCLOAK_NAMESPACE:$ROOT_DIR/platform/services/keycloak/secrets/$ENVIRONMENT/step-ca-root-ca.enc.yaml"
		"$MINIO_NAMESPACE:$ROOT_DIR/platform/services/minio/secrets/$ENVIRONMENT/step-ca-root-ca.enc.yaml"
		"$VELERO_NAMESPACE:$ROOT_DIR/platform/core/velero/secrets/$ENVIRONMENT/step-ca-root-ca.enc.yaml"
	)

	local target
	for target in "${targets[@]}"; do
		local namespace=${target%%:*}
		local out_file=${target#*:}

		create_sops_secret "$namespace" "step-ca-root-ca" \
			"$out_file" \
			"$(ca_bundle_secret "$namespace")"
	done
}

function render_velero_bsl() {
	local cert_file=$1
	local ca_cert

	ca_cert=$(base64 -w0 <"$cert_file")

	cat <<EOF >"$ROOT_DIR/platform/core/velero/base/backupstoragelocation.yaml"
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

function create_minio_secret() {
	local config

	config=$(
		cat <<EOF
  config.env: |
    export MINIO_ACCESS_KEY="minio-root-$(openssl rand -hex 8)"
    export MINIO_SECRET_KEY="$(openssl rand -base64 48 | tr -d '\n')"
EOF
	)

	create_sops_secret "$MINIO_NAMESPACE" "minio-env-configuration" \
		"$ROOT_DIR/platform/services/minio/secrets/$ENVIRONMENT/minio-env-configuration.enc.yaml" \
		"$(opaque_secret "$MINIO_NAMESPACE" "minio-env-configuration" "$config")"
}

function create_velero_secret() {
	local credentials

	credentials=$(
		cat <<EOF
  cloud: |
    [default]
    aws_access_key_id=$(rand_alnum 16)
    aws_secret_access_key=$(rand_alnum 32)
EOF
	)

	create_sops_secret "$VELERO_NAMESPACE" "cloud-credentials" \
		"$ROOT_DIR/platform/core/velero/secrets/$ENVIRONMENT/cloud-credentials.enc.yaml" \
		"$(opaque_secret "$VELERO_NAMESPACE" "cloud-credentials" "$credentials")"
}

function create_forge_db_secrets() {
	local forge_db_secret_dir="$ROOT_DIR/platform/services/forge-db/secrets/$ENVIRONMENT"
	local keycloak_secret_dir="$ROOT_DIR/platform/services/keycloak/secrets/$ENVIRONMENT"
	local backup_s3
	local keycloak_password

	backup_s3=$(
		cat <<EOF
  access-key-id: $(rand_alnum 16)
  secret-access-key: $(rand_alnum 32)
EOF
	)

	create_sops_secret "$FORGE_DB_NAMESPACE" "forge-db-backup-s3" \
		"$forge_db_secret_dir/forge-db-backup-s3.enc.yaml" \
		"$(opaque_secret "$FORGE_DB_NAMESPACE" "forge-db-backup-s3" "$backup_s3")"

	create_sops_secret "$FORGE_DB_NAMESPACE" "forge-cnpg-superuser" \
		"$forge_db_secret_dir/forge-cnpg-superuser.enc.yaml" \
		"$(basic_auth_secret "$FORGE_DB_NAMESPACE" "forge-cnpg-superuser" "postgres" "$(rand_alnum 32)")"

	keycloak_password=$(rand_alnum 32)
	create_sops_secret "$FORGE_DB_NAMESPACE" "keycloak-db" \
		"$forge_db_secret_dir/keycloak-db.enc.yaml" \
		"$(basic_auth_secret "$FORGE_DB_NAMESPACE" "keycloak-db" "keycloak" "$keycloak_password")"
	create_sops_secret "$KEYCLOAK_NAMESPACE" "keycloak-db" \
		"$keycloak_secret_dir/keycloak-db.enc.yaml" \
		"$(basic_auth_secret "$KEYCLOAK_NAMESPACE" "keycloak-db" "keycloak" "$keycloak_password")"
}

function create_keycloak_secrets() {
	create_sops_secret "$KEYCLOAK_NAMESPACE" "keycloak-admin" \
		"$ROOT_DIR/platform/services/keycloak/secrets/$ENVIRONMENT/keycloak-admin.enc.yaml" \
		"$(basic_auth_secret "$KEYCLOAK_NAMESPACE" "keycloak-admin" "admin" "$(rand_alnum 16)")"
}

function create_argocd_secrets() {
	local secret=$(
		cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: argocd-keycloak-oidc
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: argocd
type: Opaque
stringData:
  clientSecret: $(rand_alnum 32)
EOF
	)

	create_sops_secret "$ARGOCD_NAMESPACE" "argocd-keycloak-oidc" \
		"$ROOT_DIR/platform/services/argocd/secrets/$ENVIRONMENT/argocd-keycloak-oidc.enc.yaml" \
		"$secret"
}

function create_gitops_artifacts() {
	create_minio_secret
	create_velero_secret
	render_velero_bsl "$CERT_FILE"
	create_forge_db_secrets
	create_keycloak_secrets
	create_argocd_secrets
}

require_env \
	ENVIRONMENT \
	SOPS_AGE_KEY \
	SSH_REPO_KEY \
	GIT_REPO_URL \
	CF_API_KEY \
	EXT_DNS_TSIG_KEY \
	CERT_MGR_TSIG_KEY

wait_for_cluster
bootstrap_argocd_access
bootstrap_dns_secrets
ensure_step_ca_files
distribute_step_ca_certificates
create_gitops_artifacts

echo "[Forge] Done"
