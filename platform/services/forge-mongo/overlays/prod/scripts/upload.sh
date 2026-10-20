#!/bin/sh
# Uploads the archive from dump.sh to object storage (any S3-compatible
# service), checks it arrived intact, then deletes copies older than
# RETENTION_DAYS. Runs in the rclone image.
#
# Environment: S3_BUCKET, RETENTION_DAYS, and rclone's RCLONE_CONFIG_STORE_*
# variables (endpoint, credentials). Pruning happens last, after a verified
# upload, so a failing run can never leave the bucket empty.
set -eu

archive=/dump/forge-mongo.archive.gz
[ -s "$archive" ] || {
	echo "no archive to upload" >&2
	exit 1
}

dest="store:${S3_BUCKET}/forge-mongo"
name="forge-mongo-$(date -u +%Y%m%dT%H%M%SZ).archive.gz"

rclone copyto "$archive" "$dest/$name"

local_bytes=$(wc -c <"$archive")
stored_bytes=$(rclone size --json "$dest/$name" | sed -n 's/.*"bytes":\([0-9]*\).*/\1/p')
[ "$local_bytes" = "$stored_bytes" ] || {
	echo "stored size ($stored_bytes) differs from the archive ($local_bytes)" >&2
	exit 1
}
echo "uploaded $name ($stored_bytes bytes)"

rclone delete "$dest" --min-age "${RETENTION_DAYS}d"
echo "kept:"
rclone lsl "$dest"
