# Civo v2 Bootstrap Runbook

This runbook describes a clean bootstrap of the v2.0 reference environment and
the checkpoints used to decide whether it is safe to continue. It supplements
the [Civo v2 Quick Start](01-quickstart.md), which contains the complete command
sequence.

Use this runbook for a new Civo development environment. For an existing
environment, use the [v2 Upgrade Runbook](upgrade-runbook.md).

## Scope and safety

The bootstrap workflow changes several systems:

- Pulumi state and billable Civo resources
- The operator's `~/.kube/config`
- A local WireGuard interface and system forwarding configuration
- Kubernetes resources and bootstrap secrets
- SOPS-encrypted files when required secrets do not already exist
- Generated, ignored manifests and Pulumi output files in the working tree

Run it from a dedicated, reviewed checkout with a clean Git status. Do not use a
production account or shared cluster as a bootstrap experiment.

## Ownership boundaries

The clean bootstrap crosses four ownership domains:

| Domain | Owner | Examples |
| --- | --- | --- |
| Cloud infrastructure | Pulumi | Network, cluster, node pool, firewalls, WireGuard instance |
| Bootstrap state | Repository scripts and operator | Kubeconfig merge, initial credentials, trust wiring |
| Desired Kubernetes state | Repository manifests | Controllers, configuration, operators, services |
| Runtime state | Kubernetes and service controllers | Pods, certificates, endpoints, load-balancer assignments |

When a checkpoint fails, change the owning declaration or external dependency.
Do not patch an unrelated layer merely to make the next command proceed.

## 1. Establish a clean source state

Confirm the intended release or reviewed branch and a clean working tree:

```bash
git branch --show-current
git status --short
git log -1 --oneline
```

Historical encrypted development secrets are part of the repository. Confirm
that the configured age identity is authorized to decrypt the selected
environment before changing infrastructure.

### Checkpoint

- The checkout identifies the intended release.
- There are no unexplained local modifications.
- The operator knows which encrypted files are expected for the environment.

## 2. Confirm external ownership and access

Complete the account, key, DNS, and network checks in
[Prerequisites](00-prerequisites.md). In particular, verify:

- Pulumi is logged in to the intended backend.
- `CIVO_TOKEN` addresses the intended account.
- The Git repository SSH key has read access.
- The SOPS age identity decrypts the selected environment.
- Cloudflare contains the intended public zone.
- Pi-hole answers client queries on port 53.
- BIND answers authoritatively and accepts the configured RFC2136 keys on port
  5335.
- Civo, tunnel, home, Pod, and Service networks do not overlap.

### Checkpoint

Do not provision the cluster until cloud identity, secret decryption, and both
DNS listeners have been verified independently.

## 3. Prepare local bootstrap state

Create the Python environment and install both Pulumi projects' dependencies as
shown in the quick start. Generate the ignored WireGuard peer key pair before
previewing the Civo cluster.

Run the configurator:

```bash
make configure
```

Review `.env` using the [Configuration Reference](03-configuration-reference.md).
Use absolute file paths and preserve the `.env` file only in secure local
storage.

Create or select the same `PULUMI_STACK` in both Pulumi projects. The projects
have separate state even though their stack names match.

### Checkpoint

- `.wireguard/local.key` and `.wireguard/local.pub` exist with restrictive
  permissions.
- Both Pulumi projects select the intended stack.
- `.env` selects `CLOUD=civo` and an existing Civo overlay such as `dev`.
- All configured paths are absolute and readable.

## 4. Review Pulumi changes

Run `pulumi preview` separately in the foundation and cluster projects. For a
new Civo environment, the cluster preview should include the intended:

- Private network and CIDR
- Managed Kubernetes cluster and node pool
- Cluster and private load-balancer firewalls
- WireGuard firewall, SSH key, and gateway when enabled

Record or review the selected region, sizes, Kubernetes version, and resource
names. The generated name prefix is
`ORG_NAME-SYSTEM_NAME-ENVIRONMENT`.

### Checkpoint

Stop if the preview proposes deleting or replacing unrelated resources, uses an
unexpected account or region, or selects a network that overlaps an existing
route.

## 5. Run the creation workflow

From the repository root:

```bash
make create-universe
```

The command is intentionally sequential. Treat each stage boundary as a
diagnostic boundary rather than restarting the entire workflow immediately.

## 6. Foundation stage

The workflow first applies the foundation Pulumi project, writes available
Pulumi outputs to `.env.pulumi.generated`, and renders provider values used by
later stages.

For Civo, most managed infrastructure belongs to the cluster project. A small
or empty foundation update is therefore expected.

### Checkpoint

- The foundation stack update succeeds.
- `.env.pulumi.generated` is created locally.
- Generated provider values contain no unresolved placeholders.

## 7. Cluster and bootstrap-secret stage

The cluster project creates the Civo infrastructure. The workflow then:

1. Retrieves the secret kubeconfig output.
2. Normalizes its cluster, user, and context names.
3. Merges it into `~/.kube/config`.
4. Selects the new context.
5. Refreshes `.env.pulumi.generated` from cluster outputs.
6. Creates initial Kubernetes secrets and prepares encrypted platform secrets.

The kubeconfig merge preserves unrelated contexts while replacing stale entries
for the generated cluster name.

### Checkpoint

```bash
kubectl config current-context
kubectl get nodes -o wide
```

- The active context is the generated cluster name.
- Every expected node reaches `Ready`.
- Generated outputs include the network CIDR, private load-balancer firewall,
  and WireGuard addresses when enabled.
- `git status --short` shows no unexpected plaintext or key material.

If new `.enc.yaml` resources were intentionally created, review their paths and
SOPS metadata. Never commit `.env`, `.env.pulumi.generated`, kubeconfig data,
WireGuard private keys, CA private keys, or decrypted manifests.

## 8. WireGuard stage

The Civo setup waits for the gateway's SSH service and public key, writes the
gateway and local peer configurations, enables IPv4 forwarding, and restarts
both WireGuard interfaces.

The generated tunnel assigns:

- The first usable tunnel address to the Civo gateway
- The second usable tunnel address to the local peer

The local interface is named `wg-civo`. The cloud gateway interface is `wg0`.

### Operator pause

The workflow pauses after tunnel configuration. The prompt still contains
legacy AWS wording. Before pressing Enter, verify the actual Civo path:

In a second terminal, load the configured and generated values:

```bash
set -a
source .env
source .env.pulumi.generated
set +a
```

Then run:

```bash
sudo wg show wg-civo
ping -c 2 "$WIREGUARD_PRIVATE_IP"
dig @"$INT_DNS_HOST" -p 5335 "$INTERNAL_DOMAIN" SOA
```

Also verify from the gateway that it can reach the internal DNS host on TCP and
UDP ports 53 and 5335. Confirm that forwarding and source NAT rules are
persistent, not merely present in live firewall state.

### Checkpoint

Do not continue unless the latest WireGuard handshake is current, the gateway
and home network can exchange replies, and authoritative DNS is reachable from
the Civo path.

## 9. Platform core stage

The first Kubernetes phase creates the bootstrap namespaces and applies:

- Private and public ingress-nginx controllers
- Internal and external ExternalDNS controllers
- step-ca
- cert-manager
- Velero core resources

For Civo, the workflow waits for ingress load balancers and discovers the
private ingress address rather than trusting the public address in Service
status.

### Checkpoint

```bash
kubectl -n ingress-nginx get pods,services -o wide
kubectl -n external-dns get pods
kubectl -n cert-manager get pods
kubectl -n step-ca get pods
```

- Both ingress controllers are running.
- Both ingress Services receive load balancers.
- The private ingress load balancer uses the intended private firewall.
- Core controller Pods become ready.

If a load balancer remains pending, inspect its Service events and Civo state.
Do not assign an arbitrary private address to a Civo load balancer.

## 10. Configuration and operator stages

The workflow applies provider configuration and the MinIO, CloudNativePG,
MongoDB Community, Keycloak, and RabbitMQ operators. It waits for their required
CRDs and the CloudNativePG controller before continuing.

### Checkpoint

```bash
kubectl get customresourcedefinitions \
    keycloaks.k8s.keycloak.org \
    rabbitmqclusters.rabbitmq.com \
    clusters.postgresql.cnpg.io \
    tenants.minio.min.io \
    mongodbcommunity.mongodbcommunity.mongodb.com
```

All listed CRDs must be established. Investigate an unhealthy operator before
applying dependent services manually.

## 11. Platform-services stage

The first service pass creates shared services while suppressing publication of
unknown Civo private targets. The workflow then discovers private load-balancer
addresses for RabbitMQ, MongoDB, and PostgreSQL and performs a second render and
apply with DNS publication enabled.

The MinIO S3 hostname uses the discovered private ingress address rather than a
dedicated service load balancer.

### Checkpoint

The workflow reports private targets for AMQP, MongoDB, PostgreSQL, and S3. Each
target must be private and inside the configured Civo network.

```bash
kubectl get services -A | grep LoadBalancer
kubectl get pods -A
```

See [Civo dev private service DNS](../clusters/single/civo/dev/README.md) for
the two-pass publication behavior.

## 12. step-ca trust stage

After step-ca is available, bootstrap extracts its root certificate, creates the
cert-manager trust secret, and patches the internal ACME ClusterIssuer with the
CA bundle.

### Checkpoint

```bash
kubectl get clusterissuer step-ca-int-acme
kubectl get certificates -A
kubectl get challenges.acme.cert-manager.io -A
```

The internal issuer must become ready. DNS-01 challenges should complete through
the authoritative BIND listener on port 5335.

## 13. End-to-end validation

The script's final verification is deliberately basic. Complete the validation
section of the [Quick Start](01-quickstart.md), including:

- Nodes and Pods
- Both ingress controllers
- WireGuard handshake and private routing
- Public and internal DNS answers
- Private load-balancer targets
- ClusterIssuer and Certificate readiness
- Public Keycloak and private Argo CD and MinIO endpoints

Allow controllers time to reconcile. Diagnose a failed dependency chain from
the earliest failing boundary: route, DNS, challenge, certificate, ingress,
then application.

## Safe recovery after failure

The creation workflow is designed to converge, but a rerun still updates cloud,
network, and cluster state. Before rerunning it:

1. Identify the stage that failed.
2. Inspect the owning system's events or logs.
3. Correct the external dependency or desired declaration.
4. Run both Pulumi previews again if infrastructure may have changed.
5. Confirm the intended kubeconfig context.
6. Rerun only when the proposed operations are understood.

For a failure isolated to the shared-service phase, use:

```bash
./scripts/create.sh --platform-services
```

Do not use `--adopt-service-fields` during a clean bootstrap and do not use it as
a general conflict override.

## Bootstrap completion record

Record the following outside the repository's plaintext files:

- Git revision deployed
- Pulumi backend, organization, project stacks, and update identifiers
- Civo account, region, network, cluster, and gateway identifiers
- Kubeconfig context name
- Public and private ingress addresses
- Internal DNS and WireGuard verification results
- Certificate and issuer status
- Location and recovery process for SOPS, repository, WireGuard, and CA keys

The environment is ready for use only after the end-to-end checks pass, not
merely because the creation script reached its final message.
