# Aetheric Forge GitOps Bootstrap

Aetheric Forge GitOps Bootstrap provides a deterministic foundation for building and operating Kubernetes clusters using GitOps principles.

The project establishes the minimum control-plane services required to bootstrap and manage a cluster through Argo CD while maintaining clear ownership boundaries between infrastructure provisioning, bootstrap operations, and GitOps-managed workloads.

## Core Capabilities

- Kubernetes infrastructure provisioning with Pulumi
- GitOps control plane deployment using Argo CD
- Automated DNS management for internal and public domains
- Internal PKI and ACME services using step-ca
- Ingress and load balancing support
- WireGuard-based private administration access
- Declarative application and platform reconciliation

## Design Principles

- Deterministic cluster rebuilds
- Minimal manual intervention
- Explicit ownership boundaries
- Reproducible environments
- GitOps-first operations
- Clean teardown and recovery

## Architecture

The bootstrap process establishes a minimal operational control plane.

```text
Git Repository
      │
      ▼
   Argo CD
      │
 ┌────┼────┐
 ▼    ▼    ▼
DNS  PKI  Networking
 │    │       │
BIND step-ca MetalLB
```

Bootstrap installs foundational services only. Ongoing configuration and platform management are performed through GitOps reconciliation.

## Documentation

Project documentation is located in the `docs/` directory.

Key references:

- Architecture Guide
- Operations Guide
- WireGuard Operations
- GitHub and Argo CD Bootstrap
- Environment Configuration
- Release Notes

## Releases

Release notes are maintained under:

```text
docs/release-notes/
```

Git tags are considered the authoritative source for released versions.

## Quick Start

1. Review prerequisites.
2. Provision infrastructure using Pulumi.
3. Establish WireGuard connectivity.
4. Deploy platform manifests.
5. Validate Argo CD reconciliation.

Detailed deployment instructions are available in the project documentation.

## License

See repository licensing information for details.
