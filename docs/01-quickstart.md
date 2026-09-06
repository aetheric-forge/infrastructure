# Civo v2 Quick Start

This guide is the shortest supported path to the Aetheric Forge v2.0 reference
environment: a Civo Kubernetes development cluster connected to an existing
private DNS network through WireGuard.

It assumes that you understand which external systems the platform will change.
For requirements and configuration semantics, first read:

1. [Deployment Models](02-deployment-models.md)
2. [Prerequisites](00-prerequisites.md)
3. [Configuration Reference](03-configuration-reference.md)

The creation command provisions billable cloud resources, merges kubeconfig
content, installs a local WireGuard configuration with `sudo`, creates or
applies Kubernetes secrets, and applies the platform manifests. Review the
configuration and Pulumi previews before running it.

## 1. Clone the repository

Clone the repository that Argo CD will be authorized to read, then enter its
root directory:

```bash
git clone git@github.com:aetheric-forge/infrastructure.git
cd infrastructure
```

For a released installation, check out the intended release tag. For release
review, use the branch being reviewed.

## 2. Prepare the Python environment

The Pulumi project definitions use the repository-root `.venv`:

```bash
python3 -m venv .venv
. .venv/bin/activate
python3 -m pip install --upgrade pip
python3 -m pip install -r scripts/pulumi/foundation/requirements.txt
python3 -m pip install -r scripts/pulumi/cluster/requirements.txt
```

Confirm that the remaining tools listed in
[Prerequisites](00-prerequisites.md) are already available.

## 3. Authenticate external providers

Log in to the Pulumi backend you intend to use:

```bash
pulumi login
```

Export a scoped Civo API token in the deployment shell:

```bash
export CIVO_TOKEN="..."
```

Do not add the token to the repository or commit it in a Pulumi stack file.

Ensure that the Cloudflare token, two RFC2136 TSIG secrets, repository SSH key,
and SOPS age identity required by the configurator are ready.

## 4. Create the local WireGuard key pair

The Civo Pulumi program needs the local peer's public key before it can create
the gateway. Generate this ignored key pair once:

```bash
install -d -m 700 .wireguard
if [[ ! -s .wireguard/local.key || ! -s .wireguard/local.pub ]]; then
    umask 077
    wg genkey \
        | tee .wireguard/local.key \
        | wg pubkey > .wireguard/local.pub
fi
```

Keep `.wireguard/local.key` private. The `.wireguard/` directory is ignored by
Git.

This key pair is separate from the SSH public key installed on the gateway.

## 5. Configure the deployment

Run the interactive configurator:

```bash
make configure
```

Select `civo` and `dev` for the v2.0 reference path. Use absolute paths for the
repository SSH key, SOPS age identity, WireGuard gateway SSH public key, and any
supplied step-ca files.

Afterward, inspect `.env` locally. Do not paste or commit its secret values.
At minimum, confirm:

- `CLOUD=civo`
- `ENVIRONMENT=dev`
- The Civo, WireGuard, and local networks do not overlap
- `WIREGUARD__LOCAL_CIDRS` contains one IPv4 CIDR
- `INT_DNS_HOST` identifies the BIND/Pi-hole host without a port suffix
- Every configured key path is absolute and readable

The reference manifests still contain some `aethericforge.ca` development
hostnames. Use the reference domains for this quick start. Deploying under a
different base domain requires a separate manifest and generated-secret review.

## 6. Validate credentials and connectivity

Load the non-generated configuration into the current shell:

```bash
set -a
source .env
set +a
```

Confirm that the repository key can read the desired Git repository:

```bash
GIT_SSH_COMMAND="ssh -i $SSH_REPO_KEY -o IdentitiesOnly=yes" \
    git ls-remote "$GIT_REPO_URL" HEAD
```

Confirm that the age identity decrypts an existing development secret without
printing it:

```bash
SOPS_AGE_KEY_FILE="$SOPS_AGE_KEY" \
    sops --decrypt \
    platform/core/step-ca/certs/dev/step-ca-root-ca.enc.yaml \
    >/dev/null
```

Check ordinary internal resolution on port 53 and the authoritative BIND
listener on port 5335:

```bash
dig @"$INT_DNS_HOST" "$INTERNAL_DOMAIN" SOA
dig @"$INT_DNS_HOST" -p 5335 "$INTERNAL_DOMAIN" SOA
```

Both queries must succeed before bootstrap. The second response should be
authoritative.

## 7. Select or create both Pulumi stacks

The foundation and cluster directories are separate Pulumi projects. Each needs
a stack matching `PULUMI_STACK`:

```bash
(
    cd scripts/pulumi/foundation
    pulumi stack select "$PULUMI_STACK" \
        || pulumi stack init "$PULUMI_STACK"
)

(
    cd scripts/pulumi/cluster
    pulumi stack select "$PULUMI_STACK" \
        || pulumi stack init "$PULUMI_STACK"
)
```

Pulumi stack configuration files under these project directories are generated
operator state and are ignored by Git.

## 8. Review the infrastructure previews

Preview each project before allowing the bootstrap to update it:

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

For the Civo reference path, confirm that the cluster preview describes the
intended region, private network, cluster, node pool, firewalls, and WireGuard
gateway. Stop if Pulumi proposes replacing an existing network, cluster, or
gateway unexpectedly.

## 9. Create and bootstrap the platform

From the repository root, run:

```bash
make create-universe
```

The workflow performs these stages:

1. Applies the foundation Pulumi project and generates initial local outputs.
2. Creates or updates the Civo network, cluster, firewalls, and WireGuard
   gateway.
3. Merges the cluster kubeconfig into `~/.kube/config`.
4. Regenerates `.env.pulumi.generated` from cluster outputs.
5. Creates bootstrap secrets and prepares SOPS-encrypted platform secrets.
6. Configures and starts the local `wg-civo` peer.
7. Applies controllers, platform configuration, operators, and services.
8. Discovers Civo private load-balancer addresses and republishes service DNS
   targets.
9. Installs the step-ca trust bundle into cert-manager and runs basic
   verification.

The WireGuard stage pauses for operator confirmation. Despite the legacy AWS
wording currently shown by the prompt, use this pause to verify that the cloud
gateway can reach the home network and that the required DNS forwarding and
firewall rules are active. Do not continue until that path works.

The script ends with `Forge is online` only after its basic checks pass. Those
checks confirm essential namespaces, step-ca deployment presence, and bootstrap
secrets; they are not a complete health assessment.

## 10. Verify the result

Confirm that the expected kubeconfig context is active and nodes are ready:

```bash
kubectl config current-context
kubectl get nodes -o wide
kubectl get pods -A
```

Inspect the ingress controllers and their load balancers:

```bash
kubectl -n ingress-nginx get services -o wide
kubectl -n ingress-nginx get pods -o wide
```

Confirm issuer and certificate state:

```bash
kubectl get clusterissuers
kubectl get certificates -A
kubectl get challenges.acme.cert-manager.io -A
```

Load the generated cloud outputs and check the tunnel:

```bash
set -a
source .env.pulumi.generated
set +a

sudo wg show wg-civo
ping -c 2 "$WIREGUARD_PRIVATE_IP"
```

Check reference DNS records through the internal resolver:

```bash
dig @"$INT_DNS_HOST" "argocd-${ENVIRONMENT}.${INTERNAL_DOMAIN}" A
dig @"$INT_DNS_HOST" "console-${ENVIRONMENT}.${INTERNAL_DOMAIN}" A
dig @"$INT_DNS_HOST" "s3-${ENVIRONMENT}.${INTERNAL_DOMAIN}" A
dig @"$INT_DNS_HOST" "amqp-${ENVIRONMENT}.${INTERNAL_DOMAIN}" A
dig @"$INT_DNS_HOST" "forge-db-${ENVIRONMENT}.${INTERNAL_DOMAIN}" A
dig @"$INT_DNS_HOST" "forge-mongo-${ENVIRONMENT}.${INTERNAL_DOMAIN}" A
```

The private answers must be private addresses in the intended Civo network,
not the publicly routable addresses shown in Kubernetes LoadBalancer status.

Check the public identity endpoint using the public resolver:

```bash
dig "sso-${ENVIRONMENT}.${EXTERNAL_DOMAIN}" A
```

Allow time for DNS propagation, controller reconciliation, workload startup,
and certificate issuance. A pending certificate is a signal to inspect DNS and
ACME state, not a reason to recreate networking resources blindly.

## Existing-cluster service reconciliation

Do not rerun the full creation workflow merely to update shared services. For
an existing cluster, use:

```bash
./scripts/create.sh --platform-services
```

If an upgrade reports the documented server-side-apply ownership conflicts,
review the desired service definitions and run the one-time adoption:

```bash
./scripts/create.sh --platform-services --adopt-service-fields
```

The adoption flag is not part of a normal clean bootstrap and should not be
used as a general conflict override. See
[Civo dev private service DNS](../clusters/single/civo/dev/README.md).

## Next steps

Continue with the [Bootstrap Runbook](bootstrap-runbook.md) for the detailed
operational sequence and recovery guidance. Review the
[v2.0.0 Release Notes](release-notes/v2.0.0.md) before upgrading an existing
environment.
