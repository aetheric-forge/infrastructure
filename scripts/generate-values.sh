#!/usr/bin/env bash
set -euo pipefail

source .env
source .env.pulumi.generated

OUT_DIR="platform/external-dns/generated"
mkdir -p "$OUT_DIR"

echo "⚙️ Generating external-dns values"

# INTERNAL
cat >"$OUT_DIR/internal.values.yaml" <<EOF
provider: aws

sources:
  - service
  - ingress

domainFilters:
  - ${INTERNAL_DOMAIN}

zoneIdFilters:
  - ${INTERNAL_ZONE_ID}

registry: txt
txtOwnerId: internal
policy: sync

serviceAccount:
  create: true
  name: external-dns-internal
EOF

# EXTERNAL
cat >"$OUT_DIR/external.values.yaml" <<EOF
provider: aws

sources:
  - service
  - ingress

domainFilters:
  - ${EXTERNAL_DOMAIN}

zoneIdFilters:
  - ${EXTERNAL_ZONE_ID}

registry: txt
txtOwnerId: external
policy: sync

serviceAccount:
  create: true
  name: external-dns-external
EOF

echo "✅ external-dns values generated"
