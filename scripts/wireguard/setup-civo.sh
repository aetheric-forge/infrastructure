#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/paths.sh"

set -a
source "$ROOT_DIR/.env"
source "$ROOT_DIR/.env.pulumi.generated"
set +a

STATE_DIR="$ROOT_DIR/.wireguard"
LOCAL_PRIVATE_KEY="$STATE_DIR/local.key"
LOCAL_PUBLIC_KEY="$STATE_DIR/local.pub"
REMOTE_PUBLIC_KEY="$STATE_DIR/remote.pub"
LOCAL_CONFIG="$STATE_DIR/wg-civo.conf"
REMOTE_HOST="${WIREGUARD_PUBLIC_IP:?Missing WireGuard public IP}"
REMOTE_PRIVATE_IP="${WIREGUARD_PRIVATE_IP:?Missing WireGuard private IP}"
VPC_CIDR="${NETWORK_CIDR:-10.60.0.0/24}"
HOME_CIDR="${WIREGUARD__LOCAL_CIDRS:-192.168.1.0/24}"
TUNNEL_CIDR="${WIREGUARD__TUNNEL_CIDR:-10.200.10.0/24}"
TUNNEL_PREFIX="${TUNNEL_CIDR%.*}"
LAN_INTERFACE="$(ip route get "${HOME_CIDR%/*}" | awk '{for (i=1; i<=NF; i++) if ($i == "dev") {print $(i+1); exit}}')"

test -s "$LOCAL_PRIVATE_KEY"
test -s "$LOCAL_PUBLIC_KEY"
test -n "$LAN_INTERFACE"

echo "Authenticating for local WireGuard configuration..."
sudo -v || {
	echo "Could not obtain sudo authorization for the local WireGuard setup." >&2
	exit 1
}

echo "Waiting for the Civo WireGuard gateway..."
gateway_ready=false
for _ in $(seq 1 60); do
	if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
		"civo@$REMOTE_HOST" "sudo test -s /etc/wireguard/public.key" 2>/dev/null; then
		gateway_ready=true
		break
	fi
	sleep 5
done

if [[ "$gateway_ready" != "true" ]]; then
	echo "Could not connect to civo@$REMOTE_HOST or read /etc/wireguard/public.key." >&2
	echo "Check SSH directly with: ssh civo@$REMOTE_HOST 'sudo test -s /etc/wireguard/public.key'" >&2
	exit 1
fi

echo "Civo WireGuard gateway is ready"

ssh -o BatchMode=yes "civo@$REMOTE_HOST" "sudo cat /etc/wireguard/public.key" >"$REMOTE_PUBLIC_KEY" || {
	echo "Connected to the gateway but could not retrieve its WireGuard public key." >&2
	exit 1
}

ssh -o BatchMode=yes "civo@$REMOTE_HOST" "sudo bash -s" <<EOF
set -euo pipefail
VPC_INTERFACE=\$(ip route show default | awk 'NR == 1 {print \$5}')
test -n "\$VPC_INTERFACE"
cat >/etc/wireguard/wg0.conf <<EOC
[Interface]
PrivateKey = \$(cat /etc/wireguard/private.key)
Address = ${TUNNEL_PREFIX}.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -i \${VPC_INTERFACE} -o wg0 -j ACCEPT; iptables -A FORWARD -o \${VPC_INTERFACE} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -A POSTROUTING -s ${TUNNEL_CIDR} -d ${VPC_CIDR} -o \${VPC_INTERFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -i \${VPC_INTERFACE} -o wg0 -j ACCEPT; iptables -D FORWARD -o \${VPC_INTERFACE} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -D POSTROUTING -s ${TUNNEL_CIDR} -d ${VPC_CIDR} -o \${VPC_INTERFACE} -j MASQUERADE

[Peer]
PublicKey = $(cat "$LOCAL_PUBLIC_KEY")
AllowedIPs = ${HOME_CIDR},${TUNNEL_PREFIX}.2/32
EOC
chmod 600 /etc/wireguard/wg0.conf
systemctl restart wg-quick@wg0
EOF

cat >"$LOCAL_CONFIG" <<EOF
[Interface]
PrivateKey = $(cat "$LOCAL_PRIVATE_KEY")
Address = ${TUNNEL_PREFIX}.2/24
PostUp = iptables -I FORWARD 1 -i %i -o ${LAN_INTERFACE} -d ${HOME_CIDR} -j ACCEPT; iptables -I FORWARD 1 -i ${LAN_INTERFACE} -o %i -s ${HOME_CIDR} -d ${VPC_CIDR} -j ACCEPT; iptables -t nat -A POSTROUTING -s ${TUNNEL_CIDR} -d ${HOME_CIDR} -o ${LAN_INTERFACE} -j MASQUERADE; iptables -t nat -A POSTROUTING -s ${VPC_CIDR} -d ${HOME_CIDR} -o ${LAN_INTERFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -o ${LAN_INTERFACE} -d ${HOME_CIDR} -j ACCEPT; iptables -D FORWARD -i ${LAN_INTERFACE} -o %i -s ${HOME_CIDR} -d ${VPC_CIDR} -j ACCEPT; iptables -t nat -D POSTROUTING -s ${TUNNEL_CIDR} -d ${HOME_CIDR} -o ${LAN_INTERFACE} -j MASQUERADE; iptables -t nat -D POSTROUTING -s ${VPC_CIDR} -d ${HOME_CIDR} -o ${LAN_INTERFACE} -j MASQUERADE

[Peer]
PublicKey = $(cat "$REMOTE_PUBLIC_KEY")
Endpoint = ${REMOTE_HOST}:51820
AllowedIPs = ${VPC_CIDR},${TUNNEL_PREFIX}.1/32
PersistentKeepalive = 25
EOF
chmod 600 "$LOCAL_CONFIG"

sudo -n install -m 600 "$LOCAL_CONFIG" /etc/wireguard/wg-civo.conf || {
	echo "Failed to install the local WireGuard configuration." >&2
	exit 1
}
echo 'net.ipv4.ip_forward=1' | sudo -n tee /etc/sysctl.d/99-aetheric-wireguard.conf >/dev/null
sudo -n sysctl --system >/dev/null
sudo -n systemctl enable wg-quick@wg-civo >/dev/null
sudo -n systemctl restart wg-quick@wg-civo

ping -c 2 "${TUNNEL_PREFIX}.1" >/dev/null
ping -c 2 "$REMOTE_PRIVATE_IP" >/dev/null

echo "WireGuard tunnel established"
