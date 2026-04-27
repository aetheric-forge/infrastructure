#!/usr/bin/env bash
set -euo pipefail

set -a
pwd
source ../../../.env
[[ -f ../../../.env.pulumi.generated ]] && source ../../../.env.pulumi.generated
set +a

pulumi stack select "$PULUMI_STACK"
pulumi up -y
