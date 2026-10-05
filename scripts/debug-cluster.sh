#!/usr/bin/env bash
# Run the cluster stack's `pulumi up` with full provider logging while
# polling GKE alongside it, so a create that stalls with no GCP-side
# operation can be diagnosed from files instead of by hand.
#
# Everything lands in logs/cluster-debug-<timestamp>/ (gitignored).
# pulumi-verbose.log can contain credentials, so it stays owner-only;
# the other files are made readable for sharing.
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/paths.sh"

set -a
source "$ROOT_DIR/.env"
[[ -f "$ROOT_DIR/.env.pulumi.generated" ]] && source "$ROOT_DIR/.env.pulumi.generated"
set +a

[[ "${CLOUD:-}" == "gcp" ]] || { echo "debug-cluster.sh only supports CLOUD=gcp" >&2; exit 1; }

cluster="${ORG_NAME}-${SYSTEM_NAME}-${ENVIRONMENT}"
gc=(--project "$GCP_PROJECT" --region "$GCP_REGION")
out="$ROOT_DIR/logs/cluster-debug-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$out"
chmod 755 "$ROOT_DIR/logs" "$out"

verbose="$out/pulumi-verbose.log"
(umask 077 && : >"$verbose")

echo "Logging to $out"

watch_gke() {
	while true; do
		{
			echo "===== $(date -Is)"
			gcloud container clusters describe "$cluster" "${gc[@]}" \
				--format='value(status,statusMessage)' 2>&1 || true
			echo "--- node pools"
			gcloud container node-pools list --cluster "$cluster" "${gc[@]}" \
				--format='table(name,status,statusMessage)' 2>&1 || true
			echo "--- operations not DONE"
			gcloud container operations list "${gc[@]}" --filter='status!=DONE' \
				--format='table(name,operationType,targetLink.basename(),status,startTime)' 2>&1 || true
		} >>"$out/gke-watch.log"
		sleep 20
	done
}

watch_gke &
watcher=$!
trap 'kill "$watcher" 2>/dev/null || true' EXIT

cd "$CLUSTER_DIR"
pulumi stack select "$PULUMI_STACK"

# A stalled create usually ends in Ctrl-C; let Pulumi cancel and keep going
# so the audit log is still collected.
trap 'echo "Interrupted; collecting logs..."' INT

started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
status=0
TF_LOG=DEBUG pulumi up -y --logtostderr --logflow -v=9 \
	2>>"$verbose" | tee -i "$out/pulumi-up.log" || status=$?

trap - INT

kill "$watcher" 2>/dev/null || true

# Includes calls GKE rejected outright, which never become operations.
gcloud logging read \
	"resource.type=\"gke_cluster\" AND timestamp>=\"$started\"" \
	--project "$GCP_PROJECT" \
	--format='yaml(timestamp,protoPayload.methodName,protoPayload.status)' \
	>"$out/audit.log" 2>&1 || true

chmod 644 "$out/gke-watch.log" "$out/pulumi-up.log" "$out/audit.log"
chmod 600 "$verbose"

echo "pulumi up exited $status; logs in $out"
exit "$status"
