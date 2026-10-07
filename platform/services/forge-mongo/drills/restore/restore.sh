#!/bin/sh
# Proves an archive restores, without touching the real database: starts a
# throwaway mongod on localhost, replays the archive into it (oplog included),
# and prints what came back. Needs no MongoDB credentials. Runs in the mongod
# image.
set -eu

mkdir -p /scratch/db
mongod --dbpath /scratch/db --bind_ip 127.0.0.1 --port 27018 --fork --logpath /scratch/mongod.log >/dev/null

mongorestore --host 127.0.0.1 --port 27018 --gzip --oplogReplay --archive=/dump/restore.archive.gz

echo "--- restored databases ---"
mongosh --quiet --port 27018 --eval '
	db.adminCommand({listDatabases: 1}).databases
		.filter(d => !["admin", "local", "config"].includes(d.name))
		.forEach(d => {
			const s = db.getSiblingDB(d.name);
			s.getCollectionNames().forEach(c =>
				print(d.name + "." + c + ": " + s.getCollection(c).countDocuments({}) + " documents"));
		})'
echo "restore drill finished"
