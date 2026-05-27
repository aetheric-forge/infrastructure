#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/paths.sh"

set -a
source "$ROOT_DIR/.env"
[[ -f "$ROOT_DIR/.env.pulumi.generated" ]] && source "$ROOT_DIR/.env.pulumi.generated"
set +a

pulumi stack select "$PULUMI_STACK"
pulumi up -y
