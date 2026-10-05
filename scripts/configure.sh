#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/paths.sh"

ENV_FILE="$ROOT_DIR/.env"
# Force IPv4: plain `curl ifconfig.me` returns v6 on a dual-stack/v6-only
# host, and every /32 CIDR below assumes an IPv4 address. Outbound IPv4
# still works fine behind CGNAT even with no public IPv4 for inbound.
MY_IP=$(curl -4s https://ifconfig.me || true)
MY_IP_SUFFIX="/32"
if [[ -z "$MY_IP" ]]; then
	MY_IP=$(curl -6s https://ifconfig.me || true)
	MY_IP_SUFFIX="/128"
	if [[ -n "$MY_IP" ]]; then
		echo "⚠️  No IPv4 egress detected (checked via curl -4) — falling back to this host's public IPv6 address."
		echo "    Defaults below will use /128 (this exact address). If your ISP rotates the host portion"
		echo "    (SLAAC privacy extensions), widen the WireGuard access CIDR to your ISP's /64 by hand instead."
	else
		echo "⚠️  Could not detect a public IPv4 or IPv6 address — you'll need to enter access CIDRs below by hand."
	fi
fi

echo "⚡ Aetheric Forge Configuration"

if [[ -f "$ENV_FILE" ]]; then
	echo "⚠️  Existing .env found — this will overwrite it"
	read -rp "Continue? (y/N): " confirm
	[[ "$confirm" == "y" || "$confirm" == "Y" ]] || exit 1
fi

prompt() {
	local var="$1"
	local text="$2"
	local default="${3:-}"

	local value
	if [[ -n "$default" ]]; then
		read -rp "$text [$default]: " value
		value="${value:-$default}"
	else
		read -rp "$text: " value
	fi

	if [[ -z "$value" ]]; then
		echo "❌ $var is required"
		exit 1
	fi

	echo "$value"
}

prompt_optional() {
	local var="$1"
	local text="$2"

	local value
	read -rp "$text: " value
}

TMP=$(mktemp)

CLOUD=$(prompt "CLOUD" "Cloud type (aws/civo/gcp/local)" "local")
echo "CLOUD=$CLOUD" >>"$TMP"

if [ "$CLOUD" == "aws" ]; then
	# --- AWS ---
	AWS__REGION=$(prompt "AWS__REGION" "AWS region" "ca-west-1")
	echo "AWS__REGION=$AWS_REGION" >>"$TMP"

	AWS__VPC_CIDR=$(prompt "AWS__VPC_CIDR" "AWS VPC CIDR (e.g. 10.42.0.0/16)" "10.42.0.0/16")
	echo "AWS__VPC_CIDR=$AWS__VPC_CIDR" >>"$TMP"

	K8S_VERSION=$(prompt "AWS__K8S_VERSION" "Kubernetes version" "1.34")
	echo "AWS__K8S_VERSION=$AWS__K8S_VERSION" >>"$TMP"

	# --- Nodes ---
	AWS__NODE_ARCH=$(prompt "AWS__NODE_ARCH" "Node architecture (arm64/amd64)" "arm64")
	echo "AWS__NODE_ARCH=$AWS__NODE_ARCH" >>"$TMP"

	AWS__NODE_DESIRED_SIZE=$(prompt "AWS__NODE_DESIRED_SIZE" "Node desired size" "2")
	echo "AWS__NODE_DESIRED_SIZE=$AWS__NODE_DESIRED_SIZE" >>"$TMP"

	AWS_NODE_MIN_SIZE=$(prompt "AWS__NODE_MIN_SIZE" "Node min size" "2")
	echo "AWS__NODE_MIN_SIZE=$AWS__NODE_MIN_SIZE" >>"$TMP"

	AWS__NODE_MAX_SIZE=$(prompt "AWS__NODE_MAX_SIZE" "Node max size" "4")
	echo "AWS__NODE_MAX_SIZE=$AWS__NODE_MAX_SIZE" >>"$TMP"

	AWS__CLUSTER_PUBLIC_ACCESS=$(prompt "AWS__CLUSTER_PUBLIC_ACCESS" "Cluster public access? (true/false)" "false")
	echo "AWS__CLUSTER_PUBLIC_ACCESS=$AWS__CLUSTER_PUBLIC_ACCESS" >>"$TMP"

	if [ "$AWS__CLUSTER_PUBLIC_ACCESS" = "true" ]; then
		AWS__KUBE_API_PUBLIC_ACCESS_CIDRS="$MY_IP$MY_IP_SUFFIX"
		echo "AWS__KUBE_API_PUBLIC_ACCESS_CIDRS=$AWS__KUBE_API_PUBLIC_ACCESS_CIDRS" >>"$TMP"
	fi
fi

if [ "$CLOUD" == "civo" ]; then
	CIVO_REGION=$(prompt "CIVO_REGION" "Civo region" "NYC1")
	echo "CIVO_REGION=$CIVO_REGION" >>"$TMP"

	CIVO_NODE_SIZE=$(prompt "CIVO_NODE_SIZE" "Civo Kubernetes node size" "g4s.kube.small")
	echo "CIVO_NODE_SIZE=$CIVO_NODE_SIZE" >>"$TMP"

	CIVO_NODE_COUNT=$(prompt "CIVO_NODE_COUNT" "Civo Kubernetes node count" "1")
	echo "CIVO_NODE_COUNT=$CIVO_NODE_COUNT" >>"$TMP"

	CIVO_NODE_POOL_LABEL=$(prompt "CIVO_NODE_POOL_LABEL" "Civo Kubernetes node pool label" "workers")
	echo "CIVO_NODE_POOL_LABEL=$CIVO_NODE_POOL_LABEL" >>"$TMP"

	CIVO_NETWORK_CIDR=$(prompt "CIVO_NETWORK_CIDR" "Civo private network CIDR" "10.60.0.0/24")
	echo "CIVO_NETWORK_CIDR=$CIVO_NETWORK_CIDR" >>"$TMP"
fi

if [ "$CLOUD" == "gcp" ]; then
	# --- GCP ---
	GCP_PROJECT=$(prompt "GCP_PROJECT" "GCP project ID")
	echo "GCP_PROJECT=$GCP_PROJECT" >>"$TMP"
	echo "GCP__PROJECT=$GCP_PROJECT" >>"$TMP"

	GCP_REGION=$(prompt "GCP_REGION" "GCP region" "northamerica-northeast2")
	echo "GCP_REGION=$GCP_REGION" >>"$TMP"
	echo "GCP__REGION=$GCP_REGION" >>"$TMP"

	GCP_ZONE=$(prompt "GCP_ZONE" "GCP zone" "${GCP_REGION}-a")
	echo "GCP_ZONE=$GCP_ZONE" >>"$TMP"
	echo "GCP__ZONE=$GCP_ZONE" >>"$TMP"

	GCP_VPC_CIDR=$(prompt "GCP_VPC_CIDR" "GCP VPC CIDR (e.g. 10.44.0.0/16)" "10.44.0.0/16")
	echo "GCP_VPC_CIDR=$GCP_VPC_CIDR" >>"$TMP"
	echo "GCP__VPC_CIDR=$GCP_VPC_CIDR" >>"$TMP"

	K8S_VERSION=$(prompt "K8S_VERSION" "Kubernetes version" "latest")
	echo "K8S_VERSION=$K8S_VERSION" >>"$TMP"
	echo "GCP__K8S_VERSION=$K8S_VERSION" >>"$TMP"

	GCP_NODE_MACHINE_TYPE=$(prompt "GCP_NODE_MACHINE_TYPE" "GCP node machine type" "e2-standard-4")
	echo "GCP_NODE_MACHINE_TYPE=$GCP_NODE_MACHINE_TYPE" >>"$TMP"
	echo "GCP__MACHINE_TYPE=$GCP_NODE_MACHINE_TYPE" >>"$TMP"

	NODE_DESIRED_SIZE=$(prompt "NODE_DESIRED_SIZE" "Node desired size" "2")
	echo "NODE_DESIRED_SIZE=$NODE_DESIRED_SIZE" >>"$TMP"
	echo "GCP__NODE_DESIRED=$NODE_DESIRED_SIZE" >>"$TMP"

	NODE_MIN_SIZE=$(prompt "NODE_MIN_SIZE" "Node min size" "1")
	echo "NODE_MIN_SIZE=$NODE_MIN_SIZE" >>"$TMP"
	echo "GCP__NODE_MIN=$NODE_MIN_SIZE" >>"$TMP"

	NODE_MAX_SIZE=$(prompt "NODE_MAX_SIZE" "Node max size" "4")
	echo "NODE_MAX_SIZE=$NODE_MAX_SIZE" >>"$TMP"
	echo "GCP__NODE_MAX=$NODE_MAX_SIZE" >>"$TMP"
fi

# --- Core ---
ENVIRONMENT=$(prompt "ENVIRONMENT" "Environment name" "dev")
echo "ENVIRONMENT=$ENVIRONMENT" >>"$TMP"

ORG_NAME=$(prompt "ORG_NAME" "Organization name" "aetheric-forge")
echo "ORG_NAME=$ORG_NAME" >>"$TMP"

SYSTEM_NAME=$(prompt "SYSTEM_NAME" "System name" "platform")
echo "SYSTEM_NAME=$SYSTEM_NAME" >>"$TMP"

echo "PULUMI_STACK=$ENVIRONMENT" >>"$TMP"

# --- Domain ---
BASE_DOMAIN=$(prompt "BASE_DOMAIN" "Base domain (e.g. example.com)" "aethericforge.ca")
echo "BASE_DOMAIN=$BASE_DOMAIN" >>"$TMP"

echo "INTERNAL_DOMAIN=int.$BASE_DOMAIN" >>"$TMP"
echo "EXTERNAL_DOMAIN=$BASE_DOMAIN" >>"$TMP"

# --- Kubernetes ---
# --- WireGuard ---
WIREGUARD_DEFAULT="true"
[[ "$CLOUD" == "civo" ]] && WIREGUARD_DEFAULT="true"
WIREGUARD__ENABLED=$(prompt "WIREGUARD__ENABLED" "Enable WireGuard? (true/false)" "$WIREGUARD_DEFAULT")
echo "WIREGUARD__ENABLED=$WIREGUARD__ENABLED" >>"$TMP"

if [[ "$WIREGUARD__ENABLED" == "true" ]]; then
	WG_SSH_KEY=$(prompt "WIREGUARD_SSH_KEY_NAME" "WireGuard SSH key name")
	echo "WIREGUARD__SSH_KEY_NAME=$WG_SSH_KEY" >>"$TMP"

	WG_CIDR_DEFAULT="10.200.10.0/24"
	[[ "$CLOUD" == "civo" ]] && WG_CIDR_DEFAULT="10.200.20.0/24"
	[[ "$CLOUD" == "gcp" ]] && WG_CIDR_DEFAULT="10.200.30.0/24"
	WG_CIDR=$(prompt "WIREGUARD_TUNNEL_CIDR" "WireGuard tunnel CIDR" "$WG_CIDR_DEFAULT")
	echo "WIREGUARD__TUNNEL_CIDR=$WG_CIDR" >>"$TMP"

	WG_SSH_PUBLIC_KEY_FILE=$(prompt "WIREGUARD_SSH_PUBLIC_KEY_FILE" "Wireguard SSH public key file" "$HOME/.ssh/id_ed25519.pub")
	echo "WIREGUARD__SSH_PUBLIC_KEY_FILE=$WG_SSH_PUBLIC_KEY_FILE" >>$TMP

	WG_ACCESS_CIDRS=$(prompt "WIREGUARD_ACCESS_CIDRS" "Wireguard access CIDR(s)" "$MY_IP$MY_IP_SUFFIX")
	echo "WIREGUARD__ACCESS_CIDRS=$WG_ACCESS_CIDRS" >>$TMP

	WG_LOCAL_CIDRS=$(prompt "WIREGUARD_LOCAL_CIDRS" "Local network CIDR(s)" "192.168.1.0/24")
	echo "WIREGUARD__LOCAL_CIDRS=$WG_LOCAL_CIDRS" >>$TMP
fi

# --- GitOps ---
GIT_REPO_URL=$(prompt "GIT_REPO_URL" "Git repository URL")
echo "GIT_REPO_URL=$GIT_REPO_URL" >>"$TMP"

SSH_REPO_KEY=$(prompt "SSH_REPO_KEY" "Path to repo SSH key" "~/.ssh/argocd-repo")
echo "SSH_REPO_KEY=$SSH_REPO_KEY" >>"$TMP"

SOPS_AGE_KEY=$(prompt "SOPS_AGE_KEY" "Path to SOPS key" "~/.config/sops/age/keys.txt")
echo "SOPS_AGE_KEY=$SOPS_AGE_KEY" >>"$TMP"

INT_DNS_HOST=$(prompt "INT_DNS_HOST" "Internal RFC2136 DNS server" "localhost")
echo "INT_DNS_HOST=$INT_DNS_HOST" >>"$TMP"

EXT_DNS_TSIG_KEY_NAME=$(prompt "EXT_DNS_TSIG_KEY_NAME" "external-dns RFC2136 TSIG key name (as named in BIND)" "external-dns-${ENVIRONMENT}-key")
echo "EXT_DNS_TSIG_KEY_NAME=$EXT_DNS_TSIG_KEY_NAME" >>"$TMP"

EXT_DNS_TSIG_KEY=$(prompt "EXT_DNS_TSIG_KEY" "external-dns RFC2136 TSIG key")
echo "EXT_DNS_TSIG_KEY=$EXT_DNS_TSIG_KEY" >>"$TMP"

CERT_MGR_TSIG_KEY=$(prompt "CERT_MGR_TSIG_KEY" "cert-manager RFC2136 TSIG key")
echo "CERT_MGR_TSIG_KEY=$CERT_MGR_TSIG_KEY" >>"$TMP"

CF_API_KEY=$(prompt "CF_API_TOKEN" "CloudFlare API token")
echo "CF_API_KEY=$CF_API_KEY" >>"$TMP"

STEP_CA__CERT_FILE=$(prompt_optional "STEP_CA__CERT_FILE" "Step CA root certificate file (blank to generate)")
STEP_CA__KEY_FILE=""

if [ -n "$STEP_CA__CERT_FILE" ]; then
	STEP_CA__KEY_FILE=$(prompt "STEP_CA__KEY_FILE" "Step CA root certificate key file (required)")

	if [ -z "$STEP_CA__KEY_FILE" ]; then
		die "STEP_CA__KEY_FILE is required when STEP_CA__CERT_FILE is set"
	fi
fi

echo "STEP_CA__CERT_FILE=$STEP_CA__CERT_FILE" >>"$TMP"
echo "STEP_CA__KEY_FILE=$STEP_CA__KEY_FILE" >>"$TMP"
# --- Finalize ---
mv "$TMP" "$ENV_FILE"

echo ""
echo "✅ Configuration written to $ENV_FILE"
