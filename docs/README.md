# Documentation

This index organizes the Aetheric Forge Infrastructure documentation by task.
The v2.0 reference environment is the Civo `dev` deployment.

## Start here

Read these documents in order when evaluating or deploying the platform:

1. [v2.0.0 Release Notes](release-notes/v2.0.0.md) — release scope, upgrade
   notes, operational boundaries, and validated behavior
2. [Deployment Models](02-deployment-models.md) — differences between Civo,
   local k3s, AWS, and Docker Compose
3. [Prerequisites](00-prerequisites.md) — tools, accounts, keys, and network
   planning required before configuration
4. [Configuration Reference](03-configuration-reference.md) — `.env` inputs,
   provider credentials, generated values, and current constraints
5. [Quick Start](01-quickstart.md) — abbreviated deployment path
6. [Bootstrap Runbook](bootstrap-runbook.md) — complete bootstrap sequence and
   verification

The prerequisites, deployment-model, quick-start, and bootstrap documents are
being aligned with the v2.0 Civo reference workflow. During that work, the
[v2.0.0 release notes](release-notes/v2.0.0.md) and repository implementation
remain authoritative.

## Architecture

The architecture series explains the platform independently of a particular
installation procedure:

1. [Overview](architecture/01-overview.md)
2. [Bootstrap Ownership](architecture/02-bootstrap-ownership.md)
3. [GitOps](architecture/03-gitops.md)
4. [DNS](architecture/04-dns.md)
5. [Configuration](architecture/05-configuration.md)
6. [PKI](architecture/06-pki.md)
7. [Networking](architecture/07-networking.md)
8. [Secrets](architecture/08-secrets.md)
9. [Application Delivery](architecture/09-application-delivery.md)
10. [Platform Component Catalog](architecture/10-platform-component-catalog.md)

## Deployment-specific references

- [Civo dev private service DNS](../clusters/single/civo/dev/README.md) — private
  load-balancer address discovery, two-pass DNS publication, and service-field
  adoption
- [Local k3s](local/k3s.md) — preparing an existing local k3s cluster
- [Local BIND9](local/bind9.md) — preparing an RFC2136 DNS authority
- [Local Docker development platform](../docker/README.md) — running shared
  services outside Kubernetes

## Infrastructure projects

- [Cluster Pulumi project](../scripts/pulumi/cluster/README.md)
- [Foundation Pulumi project](../scripts/pulumi/foundation/README.md)

These Pulumi project READMEs contain legacy template material and are scheduled
for replacement during the v2.0 documentation update.

## Releases

- [v2.0.0](release-notes/v2.0.0.md) — current release
- [Historical release notes](release-notes/) — records of earlier releases;
  historical statements are not current operating instructions

## Contributing

Repository contribution and validation expectations are documented in
[CONTRIBUTING.md](../CONTRIBUTING.md).
