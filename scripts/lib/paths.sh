#!/usr/bin/env bash

if [[ -z "${ROOT_DIR:-}" ]]; then
	SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	export ROOT_DIR="$(cd "$SCRIPT_LIB_DIR/../.." && pwd)"
fi

export SCRIPTS_DIR="${SCRIPTS_DIR:-$ROOT_DIR/scripts}"
export FOUNDATION_DIR="${FOUNDATION_DIR:-$SCRIPTS_DIR/pulumi/foundation}"
export CLUSTER_DIR="${CLUSTER_DIR:-$SCRIPTS_DIR/pulumi/cluster}"
