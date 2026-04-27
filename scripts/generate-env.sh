#!/usr/bin/env bash
set -euo pipefail
set -a
source ../../../.env
set +a

echo "⚙️  Generating .env.pulumi.generated"

OUTPUT_FILE="../../../.env.pulumi.generated"

# Ensure stack is selected
if [[ -z "${PULUMI_STACK:-}" ]]; then
	echo "❌ PULUMI_STACK not set. Load .env first."
	exit 1
fi

pulumi stack select "$PULUMI_STACK" >/dev/null

# Dump outputs
pulumi stack output --json >../../../.pulumi-output.json

# Start fresh
TMP=$(mktemp)

echo "# ⚠️ GENERATED FILE - DO NOT EDIT" >"$TMP"

# Convert JSON → ENV
jq -r '
  to_entries |
  .[] |
  if (.value | type) == "string" then
    "\(.key | ascii_upcase)=\(.value)"
  else
    "\(.key | ascii_upcase)=\(.value | @json)"
  end
' ../../../.pulumi-output.json >>"$TMP"

cp -f "$TMP" "$OUTPUT_FILE"
rm ../../../.pulumi-output.json

echo "✅ Wrote $OUTPUT_FILE"
