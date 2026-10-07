#!/bin/sh
# Downloads the newest MongoDB archive from object storage to /dump. Runs in
# the rclone image.
set -eu

dest="store:${S3_BUCKET}/forge-mongo"
# Only archives named by upload.sh (timestamps sort oldest to newest).
latest=$(rclone lsf "$dest" --include "forge-mongo-[0-9]*Z.archive.gz" | sort | tail -n 1)
[ -n "$latest" ] || {
	echo "no archives found in $dest" >&2
	exit 1
}
echo "restoring from $latest"
rclone copyto "$dest/$latest" /dump/restore.archive.gz
