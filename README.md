# Aetheric Forge GitOps Bootstrap

Aetheric Forge GitOps Bootstrap provides a deterministic foundation for building and operating Kubernetes clusters using GitOps principles.

The project establishes the minimum control-plane services required to bootstrap and manage a cluster through Argo CD while maintaining clear ownership boundaries between infrastructure provisioning, bootstrap operations, and GitOps-managed workloads.

## Rationale

Building and operating Kubernetes platforms often requires assembling multiple foundational services before GitOps workflows can be established. This project provides a curated bootstrap layer that enables reproducible cluster deployment while preserving clear separation between infrastructure provisioning, platform bootstrap, and ongoing GitOps-managed operations.

The goal is to reduce the complexity of establishing a production-ready control plane while maintaining deterministic rebuilds, operational transparency, and recoverability.

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

## Project Status

Current Release: **v0.8.0**

The platform currently provides a functional GitOps bootstrap layer including infrastructure provisioning, DNS, PKI, networking, ingress, WireGuard administration access, and Argo CD-based reconciliation.

Current development efforts are focused on expanding platform identity integration and completing the application services layer.

Upcoming milestones include:

- v0.8.1 — Keycloak integration and platform identity completion
- v0.9.0 — Application services and reference platform workloads

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
