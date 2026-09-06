# v2 Upgrade Runbook

This runbook covers an existing Aetheric Forge development environment moving
to the v2.0 Civo reference state or adopting later v2 fixes. It is not a generic
production migration procedure.

Read the [v2.0.0 Release Notes](release-notes/v2.0.0.md) before beginning. For a
new environment, use the [Civo v2 Bootstrap Runbook](bootstrap-runbook.md).

## Upgrade principles

- Preserve Pulumi state, SOPS identities, encrypted manifests, CA material, and
  service data.
- Preview infrastructure changes before running any workflow that invokes
  Pulumi.
- Apply normal desired state before using a migration mechanism.
- Scope field-ownership adoption to the fields named by the repository helper.
- Treat WireGuard, DNS, ACME, ingress, and application health as one dependency
  chain with separate checkpoints.
- Stop when an expected invariant fails; do not repeatedly recreate network or
  load-balancer resources.

## 1. Capture the existing state

Record:

- Current Git revision and working-tree status
- Active kubeconfig context and cluster identity
- Foundation and cluster Pulumi stack names
- Civo network, cluster, firewall, gateway, and load-balancer identifiers
- Current WireGuard configuration and handshake state
- Public and private DNS answers
- ClusterIssuer and Certificate status
- Current service health and persistent-volume state

Useful read-only checks include:

```bash
git status --short
git log -1 --oneline
kubectl config current-context
kubectl get nodes -o wide
kubectl get pods -A
kubectl get services -A
kubectl get certificates -A
sudo wg show
```

## 2. Back up irreplaceable state

Before changing the environment, verify recovery copies of:

- Pulumi state or backend access
- SOPS age identities
- Argo CD repository SSH keys
- WireGuard private keys
- step-ca root certificate and private key
- Service data and Velero credentials
- Any encrypted manifests changed locally but not yet pushed

An encrypted file is not recoverable without its age identity. A running CA is
not a substitute for a tested backup of its root material.

Do not place backup archives or plaintext keys in the repository.

## 3. Update and review the repository

Fetch the intended v2 release or review branch without discarding local work:

```bash
git fetch --all --tags
git status --short
```

Resolve local changes deliberately before switching revisions. Review the
changes to:

- Pulumi programs
- Civo overlays
- WireGuard scripts
- DNS and certificate configuration
- CRDs and operators
- Stateful services and storage classes
- Encrypted manifests

Do not regenerate existing encrypted service credentials merely because the
repository was updated.

## 4. Review local configuration

Compare the existing `.env` with the
[Configuration Reference](03-configuration-reference.md). Confirm that it uses
the canonical variable names and absolute key paths.

For Civo, confirm:

- `CLOUD=civo`
- The intended `CIVO_REGION` and `CIVO_NETWORK_CIDR`
- One CIDR in `WIREGUARD__LOCAL_CIDRS`
- A non-overlapping `WIREGUARD__TUNNEL_CIDR`
- Correct repository, SOPS, Cloudflare, TSIG, and step-ca inputs
- A current `CIVO_TOKEN` in the process environment

Preserve `.env.pulumi.generated` until fresh outputs have been reviewed. It is
generated state, not the authoritative place to correct an infrastructure
value.

Load the existing inputs and outputs into the upgrade shell:

```bash
set -a
source .env
source .env.pulumi.generated
set +a
```

## 5. Preview both Pulumi projects

Activate the repository Python environment and select the existing stack in
each Pulumi project. Never initialize a replacement stack as a shortcut when
the existing one cannot be found.

Run:

```bash
(
    cd scripts/pulumi/foundation
    pulumi preview
)

(
    cd scripts/pulumi/cluster
    pulumi preview
)
```

Expected code or provider normalization may appear as an update. Stop if the
preview proposes replacing the private network, cluster, gateway, persistent
storage, or unrelated resources without an understood migration reason.

## 6. Choose the smallest supported apply path

### Complete infrastructure and platform update

The supported repository command that reconciles Pulumi, WireGuard, all
platform phases, private addresses, and step-ca trust is:

```bash
make create-universe
```

Use it only after reviewing both Pulumi previews. It may restart WireGuard and
temporarily interrupt the private dependency path.

### Shared-service-only update

When infrastructure, controllers, operators, and WireGuard are already correct
and only shared services need reconciliation, use:

```bash
./scripts/create.sh --platform-services
```

This path requires the intended kubeconfig context, `.env`, current
`.env.pulumi.generated`, Civo authentication, and SOPS access. It does not run
Pulumi, reinstall controllers, or rewrite WireGuard.

There is currently no supported flag that applies only arbitrary core,
configuration, or operator phases. Do not invent a partial production workflow
without reviewing bootstrap ordering and dependencies.

## 7. Reconcile WireGuard changes

v2 removes network-interface name assumptions and calculates peer addresses
from the configured tunnel CIDR. The Civo setup also writes persistent gateway
forwarding and source-NAT rules required for cluster traffic to reach the home
network.

Before allowing the setup to restart either peer:

- Keep a public SSH or provider-console recovery path to the gateway.
- Preserve the existing private keys.
- Confirm the tunnel CIDR has not changed unintentionally.
- Confirm the detected cloud and LAN interfaces are correct.
- Capture the existing `PostUp` and `PostDown` rules.

After reconciliation, verify both directions before continuing:

```bash
sudo wg show wg-civo
ping -c 2 "$WIREGUARD_PRIVATE_IP"
dig @"$INT_DNS_HOST" -p 5335 "$INTERNAL_DOMAIN" SOA
```

On the gateway, confirm IPv4 forwarding and persistent `wg0.conf` rules. On the
home router, confirm forwarding between the LAN and `wg-civo` and the intended
source NAT rules. A live firewall repair that is absent from persistent
configuration is not an upgrade completion.

## 8. Apply normal service state first

Run the normal shared-service reconciliation and capture any server-side-apply
conflict exactly:

```bash
./scripts/create.sh --platform-services
```

Do not add a global `--force-conflicts` option. A conflict identifies a field
manager and field path that must be reviewed.

## 9. Adopt known service fields when required

Existing Civo environments may report conflicts for:

- MongoDB's `kubernetes.civo.com/firewall-id` Service annotation
- CloudNativePG's `spec.managed.services.additional` list

After confirming that the repository's desired values should own those fields,
run the one-time scoped migration:

```bash
./scripts/create.sh --platform-services --adopt-service-fields
```

The helper force-applies only the known migration fields under a temporary
field manager, performs the normal manifest apply, and then relinquishes the
temporary ownership. It does not authorize force-adopting unrelated conflicts.

An interrupted migration can be rerun with the same flag after its current
managed fields have been inspected.

After it succeeds, return to the normal command for future reconciliation:

```bash
./scripts/create.sh --platform-services
```

## 10. Verify private load-balancer publication

The service deployment runs twice. It first suppresses DNS publication while
Civo allocates load balancers, then discovers the private addresses for
RabbitMQ, MongoDB, and PostgreSQL and reapplies their owning resources with
publication enabled. S3 uses the private ingress address.

Confirm that the reported AMQP, MongoDB, PostgreSQL, and S3 targets:

- Are valid private IPv4 addresses
- Belong to `CIVO_NETWORK_CIDR`
- Correspond to the intended Civo load balancers
- Resolve through internal DNS after reconciliation

If discovery fails, fix the Civo or Kubernetes state and rerun. Do not publish
the public address from Kubernetes Service status as an internal target.

See [Civo dev private service DNS](../clusters/single/civo/dev/README.md).

## 11. Verify DNS and ACME

The expected reference path is:

```text
Client resolution:       Pi-hole :53 -> BIND :5335 for the internal zone
RFC2136 updates:         ExternalDNS/cert-manager -> BIND :5335
DNS-01 self-checks:      cert-manager -> BIND :5335
```

Check:

```bash
dig @"$INT_DNS_HOST" "$INTERNAL_DOMAIN" SOA
dig @"$INT_DNS_HOST" -p 5335 "$INTERNAL_DOMAIN" SOA
kubectl get clusterissuers
kubectl get certificates -A
kubectl get challenges.acme.cert-manager.io -A
```

If updates appear in BIND but challenges remain pending, compare the TXT answer
seen directly on port 5335 with cert-manager events. Do not redirect direct
RFC2136 or self-check traffic through a caching resolver.

## 12. Verify identity and services

After DNS and certificates are ready, validate:

- Public Keycloak access
- Private Argo CD access and SSO
- Private MinIO console and SSO
- Membership in `minio-admins` grants the declarative administrative policy
- S3 endpoint access
- RabbitMQ, PostgreSQL, MongoDB, and Redis readiness
- Velero backup-storage location availability

The `minio-admins` policy is now declarative. Do not repair it manually in the
console during a normal upgrade.

## 13. Completion criteria

An upgrade is complete when:

- Pulumi reports the intended state without unexplained replacements.
- The current Git revision and encrypted configuration are recorded.
- WireGuard routes and persistent firewall rules work in both directions.
- Public and private ingress use their intended load balancers.
- Internal records resolve to private targets.
- ExternalDNS and cert-manager can update BIND on port 5335.
- ClusterIssuers and Certificates are ready.
- Keycloak, Argo CD, MinIO, data services, and backups pass validation.
- A normal service reconciliation completes without the adoption flag.
- No plaintext secrets or generated local state appear in Git status.

Keep the pre-upgrade record and backups until the environment has remained
healthy through the intended observation period.
