#!/usr/bin/env bash
set -euo pipefail

# Add your kustomize validation logic here
# Example: validate all kustomize overlays
kustomize build clusters/single/dev/gitops > /dev/null
echo "Kustomize validation passed!"