# Observability (metrics and logs)

Prometheus, Grafana, Loki and Alloy run in the `monitoring` namespace on the
GCP prod cluster.

| Piece | Role | Retention |
| ----- | ---- | --------- |
| Prometheus (kube-prometheus-stack) | metrics | 7 days (and a 16 GB size cap) |
| Loki (single binary) | logs, stored in an object storage service | 14 days |
| Alloy (DaemonSet) | ships each node's pod logs to Loki | n/a |
| Grafana | UI, Keycloak login at `grafana.<internal domain>` | n/a |

Alertmanager is off. The control-plane scrape targets GKE doesn't expose
(etcd, scheduler, controller-manager, kube-proxy) are off too.

## Where things live

- `platform/operators/monitoring-crds` - the Prometheus Operator CRDs, applied in
  stage 30 so they exist before anything that uses them.
- `platform/services/monitoring/base` - the three Helm charts, with no
  environment specifics.
- `platform/services/monitoring/overlays/prod` - the Ingress, Grafana's Keycloak
  settings, and ServiceMonitors for cert-manager and RabbitMQ.
- `platform/services/monitoring/secrets/prod` - SOPS-encrypted secrets.

## Log storage is a setting, not a provider

Loki talks to object storage over the S3 API and nothing in the manifests names a
provider. Where it writes is two objects:

- `platform/services/monitoring/overlays/prod/loki-object-storage.yaml`, a ConfigMap
  with the endpoint, bucket, region and whether the endpoint is plain HTTP. It is
  not secret, so it lives in git. As shipped it points at the SeaweedFS service in
  this cluster.
- the `loki-s3` Secret (`access-key-id`, `secret-access-key`).

To keep logs somewhere else, change the ConfigMap and supply matching credentials.
If the endpoint uses a certificate from the internal CA, Loki must also be given
that CA (`http_config.ca_file` under the S3 settings); the in-cluster SeaweedFS
endpoint is plain HTTP, so it doesn't need one.

`bootstrap-secrets.sh` creates the `loki-s3` credentials one of two ways:

- If `LOKI_S3_ACCESS_KEY_ID` and `LOKI_S3_SECRET_ACCESS_KEY` are set in `.env`,
  they are used as given (for any provider you point the ConfigMap at).
- Otherwise, on a cluster running SeaweedFS, a key pair is generated and registered
  as a SeaweedFS identity limited to the `loki` bucket (see "Giving a Service Its
  Own SeaweedFS Credentials" in `docs/architecture/08-secrets.md`). Nothing needs
  setting in `.env` for this.

## First deployment

1. `make create cluster` runs `bootstrap-secrets.sh`, which writes
   `grafana-admin`, `grafana-oauth` and `loki-s3` as
   `platform/services/monitoring/secrets/prod/*.enc.yaml`, and adds a `loki` identity
   to `seaweedfs-s3-config.enc.yaml`. Commit all four files: the services stage
   reads them, and fails without them.
2. Restart SeaweedFS so it loads the new identity once the config is applied:
   `kubectl -n seaweedfs rollout restart deploy/seaweedfs-all-in-one`.
3. `make create platform` applies the CRDs, then the stack. (Do the restart in step 2
   after this apply, before checking Loki.)
4. `scripts/keycloak/bootstrap-grafana.sh` registers the `grafana` client and the
   `grafana-admins` / `grafana-viewers` groups in the internal realm. It isn't
   called by `create.sh`; run it by hand, like the SeaweedFS console one.
5. Add people to those groups in Keycloak. Anyone in neither is refused.

The Grafana admin password (user `admin`) is in the `grafana-admin` Secret and
is meant for emergencies; people sign in through Keycloak.

## Scraping RabbitMQ

The operator serves the exporter only over TLS (`prometheus-tls`, port 15691)
with the broker's own certificate. The ServiceMonitor scrapes that over HTTPS,
trusting the step-ca root and using the certificate's name
(`amqp.<internal domain>`) as the server name. This is separate from the AMQP
and AMQPS listeners and needs no client certificate.
