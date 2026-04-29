#!/usr/bin/env bash
set -euo pipefail

source ../../../.env
source ../../../.env.pulumi.generated

OUT_DIR="../../../platform/external-dns/generated"
mkdir -p "$OUT_DIR"

echo "⚙️ Generating external-dns values"

# INTERNAL
cat >"$OUT_DIR/internal.values.yaml" <<EOF
provider: rfc2136

policy: sync
registry: txt
txtOwnerId: internal-dns

domainFilters:
  - int.aethericforge.ca

rfc2136:
  host: bind-dns.platform.svc.cluster.local
  port: 53
  zone: int.aethericforge.ca
  tsigSecretSecretRef:
    - name: bind-tsig
      key: tsig-key
      

interval: 30s

logLevel: debug
EOF

# EXTERNAL
cat >"$OUT_DIR/external.values.yaml" <<EOF
provider: cloudflare

sources:
  - service
  - ingress

domainFilters:
  - ${EXTERNAL_DOMAIN}

registry: txt
txtOwnerId: external
policy: sync

serviceAccount:
  create: true
  name: external-dns-external
EOF

echo "✅ external-dns values generated"
