#!/usr/bin/env bash
set -euo pipefail

set -a
source .env
[[ -f .env.pulumi.generated ]] && source .env.pulumi.generated
set +a

cd scripts/pulumi/$1
pulumi stack select "$PULUMI_STACK"
pulumi up -y
