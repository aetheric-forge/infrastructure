#!/usr/bin/env bash

# Prints only the private IPv4 address, so callers can capture it safely.
# The Service's status address is deliberately not used: Civo reports its public IP.
civo_private_service_ip() {
	local namespace="$1" service="$2" region="${CIVO_REGION:-NYC1}"
	local load_balancer_id="" private_ip="" response=""

	: "${CIVO_TOKEN:?Missing Civo API token}"
	: "${NETWORK_CIDR:?Missing Civo network CIDR}"
	for _ in $(seq 1 60); do
		load_balancer_id=$(kubectl get service "$service" -n "$namespace" \
			-o jsonpath='{.metadata.annotations.kubernetes\.civo\.com/loadbalancer-id}' \
			2>/dev/null || true)
		if [[ -n "$load_balancer_id" ]]; then
			response=$(curl -fsS --connect-timeout 10 --max-time 20 --get \
				-H "Authorization: bearer $CIVO_TOKEN" \
				--data-urlencode "region=${region^^}" \
				"https://api.civo.com/v2/loadbalancers/$load_balancer_id" || true)
			private_ip=$(jq -r '.private_ip // empty' <<<"$response" 2>/dev/null || true)
		fi
		if [[ -n "$private_ip" ]]; then
			if ! python3 - "$private_ip" "$NETWORK_CIDR" <<'PY'
import ipaddress
import sys

try:
    address = ipaddress.ip_address(sys.argv[1])
    network = ipaddress.ip_network(sys.argv[2], strict=False)
    valid = address.version == 4 and address.is_private and address in network
except ValueError:
    valid = False
sys.exit(0 if valid else 1)
PY
			then
				echo "Invalid private address for $namespace/$service: $private_ip (expected $NETWORK_CIDR)" >&2
				return 1
			fi
			printf '%s\n' "$private_ip"
			return 0
		fi
		sleep 5
	done
	echo "Timed out waiting for the Civo private address of $namespace/$service" >&2
	return 1
}
