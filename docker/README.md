# Local Docker development platform

This Compose project runs the shared development services for Aetheric Forge
and Black Circuit using neutral `dev-*` container and volume names.

## Configure

```bash
cd docker
cp .env.example .env
```

Replace every placeholder in `.env` with a unique random value. The `.env`
file is ignored by Git.

## Validate and start

```bash
docker-compose -p dev config --quiet
docker-compose -p dev up -d --build
```

The public web applications remain bound to loopback until host NGINX is
configured:

- Aetheric Forge: `http://127.0.0.1:5100`
- Black Circuit: `http://127.0.0.1:5101`
- Keycloak: `http://127.0.0.1:8080`
- MinIO API and console: `http://127.0.0.1:9000` and `http://127.0.0.1:9001`
- RabbitMQ management: `http://127.0.0.1:15672`

Database and broker initialization runs only when their named data volumes are
empty. Changing `.env` passwords later does not rewrite credentials stored in
existing volumes.

The previous manually-created `af-dev-*` containers and volumes are not used by
this project and should be retained until the new stack passes verification.

## What this stack does and does not bootstrap

This stack only creates root-level infrastructure access:

- Postgres, MongoDB, Redis, RabbitMQ, and MinIO each start with a single
  root/admin credential (`POSTGRES_ADMIN_PASSWORD`, `MONGO_ADMIN_PASSWORD`,
  `REDIS_PASSWORD`, `RABBITMQ_PASSWORD`, `MINIO_ROOT_PASSWORD`). Keycloak's own
  Postgres database/role is the one exception provisioned automatically
  (`docker/postgresql/init/10-databases.sh`) - Keycloak needs it just to start.
- Keycloak gets its two realms (`aethericforge.ca`, `int.aethericforge.ca`) and,
  in each, one root service-account client (`forge-campus-provisioner`,
  `internal-provisioner`) with broad `realm-management` permissions
  (`docker/keycloak/bootstrap.sh`, `docker/keycloak/bootstrap-internal.sh`).

It deliberately does **not** create, or even name, any scoped per-app
resource - not the `forge-campus`/`aetheric-admin`/`minio` Keycloak clients,
the `forge-admins`/`minio-admins` groups, the `groups` client scope, the
per-app MongoDB users and databases (`forge-campus`, `maintenance`,
`aetheric-membership-*`), the `forge-campus` RabbitMQ vhost/user, or the
`forge-campus-archive` S3 bucket and its access credentials. `aetheric-admin`
and `aethericforge-web` correspondingly carry **no** static config for any of
these in `compose.yaml` - no client ID, no database name, no username, no
password. Deciding what these resources are called and creating them
end-to-end is entirely aetheric-provisioning's responsibility, using the root
credentials above; this stack does not pre-agree on identities for it to fill
in secrets for.

MinIO's and RabbitMQ's root users are named `platform-admin`, matching
Postgres/MongoDB/Keycloak - not `forge-campus`, which previously conflated
the root identity with the (now removed) scoped app identity of the same
name.

**Until aetheric-provisioning has resource providers for Mongo, Keycloak
clients, RabbitMQ, and S3** (Postgres has no application consumer yet),
`aetheric-admin` and `aethericforge-web` will start but cannot fully
function - they have no client ID, database, vhost, or bucket to connect to.
The now-removed `bootstrap-aetheric-admin.sh`, `bootstrap-minio.sh`,
`10-forge-campus.js`, and `30-aetheric-admin.js` (see git history) describe
what each app used to expect and are a reference for creating the same
resources by hand in the meantime, but the compose-level config that named
them for the apps is gone - manual creation now also means manually adding
the resulting config back to each app's environment block until
aetheric-provisioning can do it instead.

## Host NGINX and TLS

Install the host packages:

```bash
sudo apt-get update
sudo apt-get install -y nginx certbot python3-certbot-nginx
```

Install and validate the supplied proxy configuration:

```bash
sudo cp nginx/dev-sites.conf /etc/nginx/conf.d/dev-sites.conf
sudo nginx -t
sudo systemctl enable --now nginx
```

Public certificate issuance must wait until every public A/AAAA record points
to this host and ports 80 and 443 are reachable from the internet.
