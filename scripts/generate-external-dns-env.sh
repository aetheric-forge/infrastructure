#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-dev}"

PULUMI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/pulumi" && pwd)"
OUTPUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../clusters/single/${ENVIRONMENT}" && pwd)"

mkdir -p "$OUTPUT_DIR"

echo "🔧 Generating external-dns env for: $ENVIRONMENT"

cd "$PULUMI_DIR"

# (optional but smart)
pulumi stack select "$ENVIRONMENT"

INTERNAL_ZONE_ID=$(pulumi stack output internalZoneId)
EXTERNAL_ZONE_ID=$(pulumi stack output externalZoneId)

cat <<EOF > "$OUTPUT_DIR/external-dns.env"
INTERNAL_DOMAIN=int.aethericforge.ca
EXTERNAL_DOMAIN=aethericforge.ca
INTERNAL_ZONE_ID=${INTERNAL_ZONE_ID}
EXTERNAL_ZONE_ID=${EXTERNAL_ZONE_ID}
EOF

echo "✅ Wrote $OUTPUT_DIR/external-dns.env"
