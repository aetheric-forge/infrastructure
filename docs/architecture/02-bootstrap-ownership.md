# Bootstrap Ownership

Bootstrap establishes enough infrastructure, access, trust, and Kubernetes
state for the platform to operate. It is not an ownerless collection of setup
steps: every artifact belongs to a specific lifecycle.

## Ownership categories

| Category | Owner | Examples |
| --- | --- | --- |
| Infrastructure | Pulumi | Civo network, cluster, firewalls, gateway; AWS VPC and EKS |
| Operator-local | Operator and bootstrap scripts | `.env`, Pulumi outputs, kubeconfig, WireGuard keys |
| Bootstrap credentials | Bootstrap scripts | Argo CD repository key, SOPS identity, DNS provider credentials |
| Desired platform state | Version-controlled manifests | Controllers, operators, Services, Ingresses, Certificates |
| Runtime state | Kubernetes and controllers | Pods, endpoints, issued certificates, load-balancer addresses |
| External state | External operator/provider | DNS zones, home firewall, trust stores, cloud accounts |

## What bootstrap does

The v2.0 Civo workflow:

1. Applies two Pulumi projects.
2. Merges the resulting kubeconfig.
3. Creates initial Kubernetes credentials.
4. Configures WireGuard peers and forwarding.
5. Applies manifests in dependency order.
6. Discovers private Civo addresses required for internal DNS.
7. Connects cert-manager to the step-ca trust root.

These actions are imperative orchestration around declarative sources. The
scripts decide ordering; Pulumi and Kubernetes resources still describe the
desired state within their respective systems.

## Bootstrap-owned local files

The following are local or generated state and are ignored by Git:

- `.env`
- `.env.pulumi.generated`
- Pulumi stack configuration files below `scripts/pulumi/`
- Rendered phase manifests
- `.wireguard/`
- Kubeconfig material
- Plaintext CA files and backups

They must be backed up according to their recovery value, but they are not
desired-state documents to commit.

## Version-controlled secrets

SOPS-encrypted `.enc.yaml` files are an intentional exception. Their ciphertext
and metadata are version-controlled desired state. The age identity that can
decrypt them remains outside Git.

Bootstrap may create an encrypted manifest when both the Kubernetes Secret and
the expected encrypted file are absent. Existing encrypted credentials should
normally be preserved during an upgrade.

## Runtime ownership

Do not edit generated resources as if they were source:

| Runtime object | Owning declaration |
| --- | --- |
| Pod or ReplicaSet | Deployment, StatefulSet, operator resource, or chart values |
| EndpointSlice | Service selectors and healthy Pods |
| Issued TLS Secret | Certificate and issuer configuration |
| DNS record | Ingress/Service annotation and ExternalDNS configuration |
| Civo load-balancer address | Service plus Civo provider state |
| Operator-created Service | Owning custom resource and Service template |

Manual runtime changes may be useful for emergency diagnosis, but the durable
fix belongs in the owner.

## Field ownership migrations

Server-side apply records ownership at the field level. Existing Civo services
can carry ownership from an older manager for MongoDB's firewall annotation or
CloudNativePG's additional-Service list.

The `--adopt-service-fields` path exists only for those known fields. It uses a
temporary field manager and relinquishes ownership afterward. It is not a
general license to force conflicts.

## Day-two changes

- Change cloud infrastructure in Pulumi and review a preview.
- Change platform declarations in Git and reconcile the affected stage.
- Rotate encrypted credentials by updating and re-encrypting their manifests.
- Repair runtime objects through their owning declaration.
- Change home DNS, routing, and trust stores in their external configuration.

The current Civo bootstrap directly applies its staged platform manifests and
also deploys Argo CD with repository credentials. Continuous GitOps coverage is
determined by the Argo CD Applications registered for an environment; do not
assume that every directly bootstrapped object has an active Argo owner.

## Recovery rule

When a stage fails, locate the earliest broken ownership boundary. A DNS
failure may originate in routing, BIND authority, TSIG access, an ExternalDNS
declaration, or cached client resolution. Recreating a downstream certificate
or ingress does not repair those owners.

See the [Bootstrap Runbook](../bootstrap-runbook.md) and
[Upgrade Runbook](../upgrade-runbook.md) for operational checkpoints.

## Next step

Continue with [GitOps Architecture](03-gitops.md).
