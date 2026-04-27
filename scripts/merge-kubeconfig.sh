#!/usr/bin/env bash
set -euo pipefail

STACK_DIR=${1:-scripts/pulumi/cluster}

TMP=$(mktemp)

# Get fresh kubeconfig
(
	cd "$STACK_DIR"
	pulumi stack output kubeconfig --show-secrets
) >"$TMP"

# Extract names from new config
CLUSTERS=$(kubectl --kubeconfig="$TMP" config get-clusters | tail -n +2)
CONTEXTS=$(kubectl --kubeconfig="$TMP" config get-contexts -o name)
USERS=$(kubectl --kubeconfig="$TMP" config view -o jsonpath='{.users[*].name}')

# Remove existing entries
for c in $CLUSTERS; do
	kubectl config delete-cluster "$c" 2>/dev/null || true
done

for c in $CONTEXTS; do
	kubectl config delete-context "$c" 2>/dev/null || true
done

for u in $USERS; do
	kubectl config delete-user "$u" 2>/dev/null || true
done

# Merge cleanly
export KUBECONFIG="$HOME/.kube/config:$TMP"
kubectl config view --flatten >"$HOME/.kube/config.new"

mv "$HOME/.kube/config.new" "$HOME/.kube/config"
rm "$TMP"

echo "✔ kubeconfig replaced cleanly"
