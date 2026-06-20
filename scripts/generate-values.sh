#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/paths.sh"

source "$ROOT_DIR/.env"
source "$ROOT_DIR/.env.pulumi.generated"

required_vars=(
	INTERNAL_DOMAIN
	EXTERNAL_DOMAIN
	INT_DNS_HOST
)

for var in "${required_vars[@]}"; do
	if [[ -z "${!var:-}" ]]; then
		echo "❌ ${var} is not set. Run foundation Pulumi and generate-env first."
		exit 1
	fi
done

DNS_DIR="$ROOT_DIR/platform/core/external-dns/base/generated"
CM_DIR="$ROOT_DIR/platform/core/cert-manager/base/generated"
mkdir -p "$DNS_DIR"
mkdir -p "$CM_DIR"

echo "⚙️ Generating external-dns and cert-manager values"

cat >"$DNS_DIR/internal.values.yaml" <<EOF
# INTERNAL
provider:
  name: rfc2136

sources:
  - service
  - ingress

domainFilters:
  - ${INTERNAL_DOMAIN}

registry: txt
txtOwnerId: internal
policy: sync

extraArgs:
  - --rfc2136-host=${INT_DNS_HOST}
  - --rfc2136-port=5335
  - --rfc2136-zone=${INTERNAL_DOMAIN}
  - --rfc2136-tsig-secret-alg=hmac-sha256
  - --rfc2136-tsig-keyname=external-dns-${ENVIRONMENT}-key

env:
  - name: EXTERNAL_DNS_RFC2136_TSIG_SECRET
    valueFrom:
      secretKeyRef:
        name: external-dns-internal-tsig
        key: tsig-secret

serviceAccount:
  create: true
  name: external-dns-internal
EOF

# EXTERNAL
cat >"$DNS_DIR/external.values.yaml" <<EOF
provider:
  name: cloudflare

env:
  - name: CF_API_TOKEN
    valueFrom:
      secretKeyRef:
        name: cloudflare-api-token
        key: apiToken

sources:
  - service
  - ingress

domainFilters:
  - ${EXTERNAL_DOMAIN}

registry: txt
txtOwnerId: external
policy: sync

extraArgs:
  - --exclude-domains=int.aethericforge.ca

serviceAccount:
  create: true
  name: external-dns-external
EOF

cat >"$CM_DIR/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
EOF

if [ "$CLOUD" == "aws" ]; then
	cat >>"$CM_DIR/kustomization.yaml" <<EOF

patches:
- target:
    kind: ClusterIssuer
    name: step-ca-int-acme
  patch: |
    - op: replace
      path: /spec/acme/solvers/0/dns01/route53/hostedZoneID
      value: ${INTERNAL_ZONE_ID}
EOF
else
	cat >>"$CM_DIR/kustomization.yaml" <<EOF
patches: []
EOF
fi

echo "✅ external-dns values generated"
