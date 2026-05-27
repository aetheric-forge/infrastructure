#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/paths.sh"

echo "⚡ WireGuard setup"

set -a
source "$ROOT_DIR/.env"
source "$ROOT_DIR/.env.pulumi.generated"
set +a

if [[ "${WIREGUARD_ENABLED:-false}" != "true" ]]; then
	echo "WireGuard disabled, skipping"
	exit 0
fi

HOST=$WIREGUARD_PUBLIC_IP
SG=$WIREGUARD_SG_ID

echo "🌐 Opening temporary SSH access"

MY_IP=$(curl -s https://checkip.amazonaws.com)

aws ec2 authorize-security-group-ingress \
	--group-id "$SG" \
	--protocol tcp \
	--port 22 \
	--cidr "${MY_IP}/32" \
	>/dev/null 2>&1 || true

echo "🌐 Configuring remote"

WG_DIR=/etc/wireguard
ssh "ec2-user@$HOST" <<'EOF'
set -e

if command -v yum >/dev/null; then
  sudo yum install -y wireguard-tools iptables iptables-services
else
  sudo apt update && sudo apt install -y wireguard
fi

sudo mkdir -p /etc/wireguard

if [ ! -f /etc/wireguard/private.key ]; then
  sudo sh -c 'wg genkey | sudo tee /etc/wireguard/private.key | wg pubkey | sudo tee /etc/wireguard/public.key' >/dev/null
  sudo chmod 600 /etc/wireguard/private.key
fi
EOF

echo "🔑 Fetching remote public key"

WIREGUARD_STATE_DIR="$ROOT_DIR/.wireguard"
mkdir -p "$WIREGUARD_STATE_DIR"
ssh "ec2-user@$HOST" "sudo cat /etc/wireguard/public.key" >"$WIREGUARD_STATE_DIR/remote.pub"

echo "💻 Configuring local"

if [[ ! -f "$WG_DIR/private.key" ]]; then
	wg genkey | sudo tee "$WG_DIR/private.key" | wg pubkey | sudo tee "$WG_DIR/public.key" >/dev/null
	sudo chmod 600 "$WG_DIR/private.key"
fi

LOCAL_PRIV=$(sudo cat "$WG_DIR/private.key")
LOCAL_PUB=$(sudo cat "$WG_DIR/public.key")
REMOTE_PUB=$(cat "$WIREGUARD_STATE_DIR/remote.pub")

echo "⚙️ Building configs"

sudo tee "/etc/wireguard/wg0.conf" >/dev/null <<EOF
[Interface]
PrivateKey = $LOCAL_PRIV
Address = 10.200.10.2/24

[Peer]
PublicKey = $REMOTE_PUB
Endpoint = $WIREGUARD_PUBLIC_IP:51820
AllowedIPs = $AWS_VPC_CIDR,10.200.10.1/32
PersistentKeepalive = 25
EOF

sudo systemctl enable wg-quick@wg0
sudo systemctl restart wg-quick@wg0

ssh "ec2-user@$HOST" <<EOF
sudo tee /etc/wireguard/wg0.conf > /dev/null <<EOC
[Interface]
PrivateKey = \$(sudo cat /etc/wireguard/private.key)
Address = 10.200.10.1/24
ListenPort = 51820

[Peer]
PublicKey = $LOCAL_PUB
AllowedIPs = $WIREGUARD_LOCAL_CIDRS,10.200.10.2/32
EOC

sudo systemctl enable wg-quick@wg0
sudo systemctl restart wg-quick@wg0
sudo iptables -t nat -A POSTROUTING -s 10.200.10.0/24 -o ens5 -j MASQUERADE
sudo iptables -A FORWARD -i wg0 -o ens5 -j ACCEPT
sudo iptables -A FORWARD -i ens5 -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT

EOF

echo "🚀 Starting local interface"

sudo wg-quick up "$WG_DIR/wg0.conf" || true

echo "🔍 Verifying tunnel"

ping -c 2 10.200.10.1 >/dev/null

echo "🔒 Closing temporary SSH access"

aws ec2 revoke-security-group-ingress \
	--group-id "$SG" \
	--protocol tcp \
	--port 22 \
	--cidr "${MY_IP}/32" \
	>/dev/null 2>&1 || true

echo "✅ WireGuard complete"
