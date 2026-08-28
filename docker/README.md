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
