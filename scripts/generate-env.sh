#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/paths.sh"

set -a
source "$ROOT_DIR/.env"
set +a

echo "⚙️  Generating .env.pulumi.generated"

OUTPUT_FILE="$ROOT_DIR/.env.pulumi.generated"
PULUMI_OUTPUT_FILE="$ROOT_DIR/.pulumi-output.json"

# Ensure stack is selected
if [[ -z "${PULUMI_STACK:-}" ]]; then
	echo "❌ PULUMI_STACK not set. Load .env first."
	exit 1
fi

pulumi stack select "$PULUMI_STACK" >/dev/null

# Dump outputs
pulumi stack output --json >"$PULUMI_OUTPUT_FILE"

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
' "$PULUMI_OUTPUT_FILE" >>"$TMP"

cp -f "$TMP" "$OUTPUT_FILE"
rm "$PULUMI_OUTPUT_FILE"

echo "✅ Wrote $OUTPUT_FILE"
