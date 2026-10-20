#!/bin/sh
# Dumps every database, plus the oplog so the archive is one consistent point
# in time, to /dump/forge-mongo.archive.gz. Runs in the mongod image.
#
# Environment: MONGO_HOST (replicaSet/host:port), MONGO_USER, MONGO_PASSWORD.
set -eu
umask 077

# The password goes in a config file, not on the command line.
printf 'password: "%s"\n' "$MONGO_PASSWORD" >/tmp/mongodump.yaml

mongodump \
	--config /tmp/mongodump.yaml \
	--host "$MONGO_HOST" \
	--username "$MONGO_USER" \
	--authenticationDatabase admin \
	--oplog --gzip \
	--archive=/dump/forge-mongo.archive.gz

[ -s /dump/forge-mongo.archive.gz ] || {
	echo "mongodump produced no archive" >&2
	exit 1
}
echo "dumped $(wc -c </dump/forge-mongo.archive.gz) bytes"
