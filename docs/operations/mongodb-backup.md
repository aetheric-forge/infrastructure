# MongoDB backup and restore

`forge-mongo` is backed up nightly by the `mongo-backup` CronJob in the
`forge-mongo` namespace.

| | |
| --- | --- |
| What | every database, via `mongodump --oplog --gzip` (one consistent point in time) |
| When | 02:45 UTC daily |
| Where | the `mongo-backup` bucket, under `forge-mongo/forge-mongo-<UTC timestamp>.archive.gz` |
| Kept | 14 days (`RETENTION_DAYS` in the `mongo-backup-config` ConfigMap) |
| Login | MongoDB user `mongo-backup`, built-in `backup` role only |
| Storage login | SeaweedFS identity `mongo-backup`, limited to that bucket |

Old copies are deleted only after the new upload's size has been checked, so a
run that fails never leaves the bucket emptier than it found it.

The storage is a setting, not a dependency: `RCLONE_CONFIG_STORE_*` in
`mongo-backup-config` describe any S3-compatible service. Point them (and the
`mongo-backup-s3` Secret) elsewhere to change where backups go.

## Check that it is working

```
kubectl -n forge-mongo get cronjob mongo-backup
kubectl -n forge-mongo get jobs
kubectl -n forge-mongo logs job/<latest job> -c upload
```

To run one now: `kubectl -n forge-mongo create job --from=cronjob/mongo-backup mongo-backup-manual-1`.

## Prove a backup restores (do this, and repeat it now and then)

A backup nobody has restored is a guess. The drill replays the newest archive
into a throwaway `mongod` inside a pod and prints document counts. It reads only
from object storage and needs no MongoDB credentials, so it cannot touch the
real database.

```
kubectl -n forge-mongo delete job mongo-restore-drill --ignore-not-found
kubectl apply -k platform/services/forge-mongo/drills/restore
kubectl -n forge-mongo logs -f job/mongo-restore-drill -c restore
```

It ends with `restore drill finished` and a line per collection. Compare those
counts with the live database.

## Restoring for real

1. Download the archive you want (list them with `rclone lsf` against the bucket,
   or from the SeaweedFS console).
2. Restore into a new or emptied deployment; do not restore over a running
   database you still need.
3. `mongorestore --gzip --oplogReplay --archive=<file> --uri <target>`
   with an account that has the `restore` role (the `forge-mongo-admin` root
   user works).

`--oplogReplay` brings every collection to the same moment. Users and roles are
in the `admin` database, which the dump includes.

## Limits to know about

- The archives live in SeaweedFS, on one disk inside this cluster. Losing the
  cluster loses them too; keep a copy outside it if the data matters that much.
- `forge-mongo` runs as a single member, so a backup is also the only copy if
  its disk is lost.
