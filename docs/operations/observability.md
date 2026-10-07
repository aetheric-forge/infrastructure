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

Loki talks to object storage over the S3 API, and the endpoint, bucket and
credentials all come from the `loki-object-storage` Secret. Nothing in the
manifests names a provider, so changing where logs are kept means changing
that Secret. Set these in `.env` before running `bootstrap-secrets.sh`:

```
LOKI_S3_ENDPOINT=<host[:port], no scheme>
LOKI_S3_BUCKET=<existing bucket>
LOKI_S3_ACCESS_KEY_ID=...
LOKI_S3_SECRET_ACCESS_KEY=...
LOKI_S3_REGION=<optional, default us-east-1>
```

If the storage endpoint uses a certificate from the internal CA, Loki must also
be given that CA (`http_config.ca_file` under the S3 settings); that depends on
the provider and isn't set here.

## First deployment

1. Put the `LOKI_S3_*` values in `.env`.
2. `make create cluster` runs `bootstrap-secrets.sh`, which writes
   `grafana-admin`, `grafana-oauth` and `loki-object-storage` as
   `platform/services/monitoring/secrets/prod/*.enc.yaml`. Commit those files:
   the services stage reads them, and the stage fails without them.
3. `make create platform` applies the CRDs, then the stack.
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
