# Aetheric Forge Infrastructure

Aetheric Forge Infrastructure provisions and bootstraps the Kubernetes platform
used by Aetheric Forge. It combines infrastructure as code, Kubernetes
manifests, and GitOps reconciliation into a reproducible platform foundation.

The repository owns the path from infrastructure provisioning through the
initial Argo CD bootstrap. After bootstrap, Argo CD reconciles the platform's
controllers, configuration, operators, and shared services from Git.

## Current release

The current release is **v2.0.0**. Civo Kubernetes is the reference deployment
for the development platform in this release.

See the [v2.0.0 release notes](docs/release-notes/v2.0.0.md) for the complete
feature set, upgrade considerations, validation performed, and known
limitations.

## What the platform provides

- Pulumi-managed Kubernetes infrastructure for Civo and AWS
- Support for an existing local k3s cluster
- Argo CD bootstrap and GitOps reconciliation
- Public and private ingress-nginx controllers
- Public DNS through Cloudflare and internal DNS through RFC2136/BIND
- Private PKI and ACME certificate lifecycle management with step-ca and
  cert-manager
- WireGuard connectivity between cloud and private networks
- Keycloak identity and SSO integration
- Shared data and messaging services including MinIO, RabbitMQ, PostgreSQL,
  MongoDB, and Redis
- Velero backup integration
- A separate Docker Compose stack for local application development

## Deployment models

| Model | Status in v2.0 | Intended use |
| --- | --- | --- |
| Civo Kubernetes | Reference and fully exercised | Hosted development platform |
| Local k3s | Supported | Local development and laboratory deployments |
| AWS EKS | Supported legacy cloud path | AWS-based development environments |
| Docker Compose | Separate development stack | Running shared application services locally |

The Civo `dev` overlay is the release reference. Local k3s and AWS assets remain
available, but they have not received the same end-to-end v2.0 validation. See
[Deployment Models](docs/02-deployment-models.md) for their current boundaries.

## Architecture at a glance

```text
                         Git repository
                                │
                                ▼
                             Argo CD
                                │
                 ┌──────────────┼──────────────┐
                 ▼              ▼              ▼
             Controllers    Operators     Shared services

Internet ──► Public ingress ──► Public applications

Private clients ──► WireGuard ──► Private ingress and service load balancers
                         │
                         └──► Home DNS network
                                  │
                    ┌─────────────┴─────────────┐
                    ▼                           ▼
             Pi-hole resolver             BIND/RFC2136
                 port 53                    port 5335
                    │                           ▲
                    └── internal zone ──────────┘
                                                ▲
                                  ExternalDNS and cert-manager
```

Infrastructure and bootstrap scripts establish the cluster, access path, and
minimum control plane. GitOps then owns the desired platform state. Runtime
controllers own generated resources such as load balancer assignments, DNS
records, and issued certificates.

## Repository layout

| Path | Purpose |
| --- | --- |
| `scripts/` | Configuration, provisioning, bootstrap, validation, and teardown |
| `scripts/pulumi/` | Cloud infrastructure and Kubernetes cluster provisioning |
| `clusters/` | Deployment-model and environment overlays |
| `platform/` | Reusable controllers, configuration, operators, and services |
| `apps/` | Example and platform-consumer applications |
| `docs/` | Architecture, deployment, operations, and release documentation |
| `docker/` | Local Docker Compose development stack |

## Getting started

Start with the [documentation index](docs/README.md). It identifies the
reference path, supporting architecture material, local-development guides,
and the documents that are still being aligned for v2.0.

For the current bootstrap sequence, read:

1. [Deployment Models](docs/02-deployment-models.md)
2. [Prerequisites](docs/00-prerequisites.md)
3. [Configuration Reference](docs/03-configuration-reference.md)
4. [Quick Start](docs/01-quickstart.md)
5. [Bootstrap Runbook](docs/bootstrap-runbook.md)

The bootstrap runbook is still being revised for the v2.0 Civo workflow. Until
that work is complete, use the quick start together with the
[v2.0.0 release notes](docs/release-notes/v2.0.0.md) and implementation as the
authoritative description of the reference environment.

## Configuration and secrets

Local configuration, generated Pulumi output, credentials, and decrypted
secret material must not be committed. SOPS-encrypted `.enc.yaml` manifests are
intentionally tracked and are the only encrypted secret material expected in
Git.

Run the repository configuration workflow to create local inputs:

```bash
make configure
```

Provider credentials such as the Civo token remain in the operator's local
environment.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for ownership, reproducibility, testing,
and secret-handling expectations.

## License

See [LICENSE.md](LICENSE.md).
