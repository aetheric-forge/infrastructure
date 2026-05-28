#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/paths.sh"
source "$ROOT_DIR/.env"

if [ "$CLOUD" != "aws" ]; then
	exit 0
fi

CLUSTER_NAME="${ORG_NAME}-${SYSTEM_NAME}-${ENVIRONMENT}"
TMP=$(mktemp)
NORMALIZED=$(mktemp)
BASE=$(mktemp)
trap 'rm -f "$TMP" "$NORMALIZED" "$BASE"' EXIT

# Get fresh kubeconfig
(
	pulumi stack output kubeconfig --show-secrets
) >"$TMP"

ORIGINAL_CLUSTERS=$(kubectl --kubeconfig="$TMP" config get-clusters | tail -n +2)
ORIGINAL_CONTEXTS=$(kubectl --kubeconfig="$TMP" config get-contexts -o name)

kubectl --kubeconfig="$TMP" config view --raw -o json |
	jq --arg name "$CLUSTER_NAME" '
		.clusters |= map(.name = $name)
		| .users |= map(.name = $name)
		| .contexts |= map(.name = $name | .context.cluster = $name | .context.user = $name)
		| ."current-context" = $name
	' >"$NORMALIZED"
mv "$NORMALIZED" "$TMP"

# Extract names from new config
CLUSTERS=$(kubectl --kubeconfig="$TMP" config get-clusters | tail -n +2)
CONTEXTS=$(kubectl --kubeconfig="$TMP" config get-contexts -o name)
USERS=$(kubectl --kubeconfig="$TMP" config view -o jsonpath='{.users[*].name}')

if [[ -f "$HOME/.kube/config" ]]; then
	cp "$HOME/.kube/config" "$BASE"
else
	mkdir -p "$HOME/.kube"
	touch "$BASE"
fi

# Remove stale entries from the temporary base config before merging.
for c in $ORIGINAL_CLUSTERS $CLUSTERS; do
	kubectl --kubeconfig="$BASE" config delete-cluster "$c" 2>/dev/null || true
done

for c in $ORIGINAL_CONTEXTS $CONTEXTS; do
	kubectl --kubeconfig="$BASE" config delete-context "$c" 2>/dev/null || true
done

for u in $USERS; do
	kubectl --kubeconfig="$BASE" config delete-user "$u" 2>/dev/null || true
done

# Merge cleanly
export KUBECONFIG="$BASE:$TMP"
kubectl config view --flatten >"$HOME/.kube/config.new"

mv "$HOME/.kube/config.new" "$HOME/.kube/config"
kubectl config use-context "$CLUSTER_NAME" >/dev/null

echo "✔ kubeconfig replaced cleanly"
