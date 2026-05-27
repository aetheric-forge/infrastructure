#!/usr/bin/env bash
set -euo pipefail

# Add your kustomize validation logic here
# Example: validate all kustomize overlays
kustomize --enable-helm --enable-alpha-plugins --enable-exec build clusters/single/dev/gitops > /dev/null
echo "Kustomize validation passed!"