#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=".env"
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

CLUSTER_PUBLIC_ACCESS=$(prompt "CLUSTER_PUBLIC_ACCESS" "Cluster public access? (true/false)" "false")
echo "CLUSTER_PUBLIC_ACCESS=$CLUSTER_PUBLIC_ACCESS" >>"$TMP"

if [ "$CLUSTER_PUBLIC_ACCESS" = "true" ]; then
	KUBE_API_PUBLIC_ACCESS_CIDRS="$MY_IP/32"
	echo "KUBE_API_PUBLIC_ACCESS_CIDRS=$KUBE_API_PUBLIC_ACCESS_CIDRS" >>"$TMP"
fi

# --- Core ---
ENVIRONMENT=$(prompt "ENVIRONMENT" "Environment name" "dev")
echo "ENVIRONMENT=$ENVIRONMENT" >>"$TMP"

ORG_NAME=$(prompt "ORG_NAME" "Organization name" "aetheric-forge")
echo "ORG_NAME=$ORG_NAME" >>"$TMP"

SYSTEM_NAME=$(prompt "SYSTEM_NAME" "System name" "platform")
echo "SYSTEM_NAME=$SYSTEM_NAME" >>"$TMP"

echo "PULUMI_STACK=$ENVIRONMENT" >>"$TMP"

# --- AWS ---
AWS_REGION=$(prompt "AWS_REGION" "AWS region" "ca-central-1")
echo "AWS_REGION=$AWS_REGION" >>"$TMP"

# --- Domain ---
BASE_DOMAIN=$(prompt "BASE_DOMAIN" "Base domain (e.g. example.com)")
echo "BASE_DOMAIN=$BASE_DOMAIN" >>"$TMP"

echo "INTERNAL_DOMAIN=int.$BASE_DOMAIN" >>"$TMP"
echo "EXTERNAL_DOMAIN=$BASE_DOMAIN" >>"$TMP"

# --- Kubernetes ---
K8S_VERSION=$(prompt "K8S_VERSION" "Kubernetes version" "1.34")
echo "K8S_VERSION=$K8S_VERSION" >>"$TMP"

# --- Nodes ---
NODE_ARCH=$(prompt "NODE_ARCH" "Node architecture (arm64/amd64)" "arm64")
echo "NODE_ARCH=$NODE_ARCH" >>"$TMP"

NODE_DESIRED_SIZE=$(prompt "NODE_DESIRED_SIZE" "Node desired size" "1")
echo "NODE_DESIRED_SIZE=$NODE_DESIRED_SIZE" >>"$TMP"

NODE_MIN_SIZE=$(prompt "NODE_MIN_SIZE" "Node min size" "1")
echo "NODE_MIN_SIZE=$NODE_MIN_SIZE" >>"$TMP"

NODE_MAX_SIZE=$(prompt "NODE_MAX_SIZE" "Node max size" "2")
echo "NODE_MAX_SIZE=$NODE_MAX_SIZE" >>"$TMP"

# --- WireGuard ---
WIREGUARD_ENABLED=$(prompt "WIREGUARD_ENABLED" "Enable WireGuard? (true/false)" "true")
echo "WIREGUARD_ENABLED=$WIREGUARD_ENABLED" >>"$TMP"

if [[ "$WIREGUARD_ENABLED" == "true" ]]; then
	WG_SSH_KEY=$(prompt "WIREGUARD_SSH_KEY_NAME" "WireGuard SSH key name")
	echo "WIREGUARD_SSH_KEY_NAME=$WG_SSH_KEY" >>"$TMP"

	WG_CIDR=$(prompt "WIREGUARD_TUNNEL_CIDR" "WireGuard tunnel CIDR" "10.200.10.0/24")
	echo "WIREGUARD_TUNNEL_CIDR=$WG_CIDR" >>"$TMP"

	WG_SSH_PUBLIC_KEY_FILE=$(prompt "WIREGUARD_SSH_PUBLIC_KEY_FILE" "Wireguard SSH public key file" "$HOME/.ssh/id_ed25519.pub")
	echo "WIREGUARD_SSH_PUBLIC_KEY_FILE=$WG_SSH_PUBLIC_KEY_FILE" >>$TMP

	WG_ACCESS_CIDRS="$MY_IP/32"
	echo "WIREGUARD_ACCESS_CIDRS=$WG_ACCESS_CIDRS" >>$TMP

	WG_LOCAL_CIDRS=$(prompt "WIREGUARD_LOCAL_CIDRS" "Local network CIDR(s)" "192.168.1.0/24")
	echo "WIREGUARD_LOCAL_CIDRS=$WG_LOCAL_CIDRS" >>$TMP
fi

# --- GitOps ---
GIT_REPO_URL=$(prompt "GIT_REPO_URL" "Git repository URL")
echo "GIT_REPO_URL=$GIT_REPO_URL" >>"$TMP"

# --- Finalize ---
mv "$TMP" "$ENV_FILE"

echo ""
echo "✅ Configuration written to $ENV_FILE"
echo ""
echo "📋 Summary:"
echo "  ENVIRONMENT=$ENVIRONMENT"
echo "  AWS_REGION=$AWS_REGION"
echo "  BASE_DOMAIN=$BASE_DOMAIN"
echo "  NODE_ARCH=$NODE_ARCH"
echo "  WIREGUARD_ENABLED=$WIREGUARD_ENABLED"
echo "  GIT_REPO_URL=$GIT_REPO_URL"
