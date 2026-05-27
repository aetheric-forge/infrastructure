#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/paths.sh"

ENV_FILE="$ROOT_DIR/.env"
MY_IP=$(curl ifconfig.me)

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

TMP=$(mktemp)

CLOUD=$(prompt "CLOUD" "Cloud type (AWS/local)" "local")
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
		AWS__KUBE_API_PUBLIC_ACCESS_CIDRS="$MY_IP/32"
		echo "AWS__KUBE_API_PUBLIC_ACCESS_CIDRS=$AWS__KUBE_API_PUBLIC_ACCESS_CIDRS" >>"$TMP"
	fi
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
WIREGUARD__ENABLED=$(prompt "WIREGUARD__ENABLED" "Enable WireGuard? (true/false)" "true")
echo "WIREGUARD__ENABLED=$WIREGUARD__ENABLED" >>"$TMP"

if [[ "$WIREGUARD__ENABLED" == "true" ]]; then
	WG_SSH_KEY=$(prompt "WIREGUARD_SSH_KEY_NAME" "WireGuard SSH key name")
	echo "WIREGUARD__SSH_KEY_NAME=$WG_SSH_KEY" >>"$TMP"

	WG_CIDR=$(prompt "WIREGUARD_TUNNEL_CIDR" "WireGuard tunnel CIDR" "10.200.10.0/24")
	echo "WIREGUARD__TUNNEL_CIDR=$WG_CIDR" >>"$TMP"

	WG_SSH_PUBLIC_KEY_FILE=$(prompt "WIREGUARD_SSH_PUBLIC_KEY_FILE" "Wireguard SSH public key file" "$HOME/.ssh/id_ed25519.pub")
	echo "WIREGUARD__SSH_PUBLIC_KEY_FILE=$WG_SSH_PUBLIC_KEY_FILE" >>$TMP

	WG_ACCESS_CIDRS=$(prompt "WIREGUARD_ACCESS_CIDRS" "Wireguard access CIDR(s)" "$MY_IP/32")
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

TSIG_KEY=$(prompt "TSIG_KEY" "RFC2136 TSIG key")
echo "TSIG_KEY=$TSIG_KEY" >>"$TMP"

CF_API_KEY=$(prompt "CF_API_TOKEN" "CloudFlare API token")
echo "CF_API_KEY=$CF_API_KEY" >>"$TMP"

# --- Finalize ---
mv "$TMP" "$ENV_FILE"

echo ""
echo "✅ Configuration written to $ENV_FILE"
