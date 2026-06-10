# Architecture Overview

Aetheric Forge is a GitOps platform designed to provide a reproducible, self-managing Kubernetes foundation.

Rather than focusing on individual technologies, Aetheric Forge organizes infrastructure around a clear ownership model.

Understanding these ownership boundaries is the key to understanding the platform.

---

## Core Philosophy

The platform is built around a simple principle:

> Bootstrap installs the minimum required foundation. GitOps manages everything else.

The bootstrap process establishes a functioning control plane.

Once that control plane is operational, Argo CD becomes responsible for deploying, reconciling, and maintaining the platform.

---

## Architectural Layers

The platform can be viewed as a series of layers.

```text
┌─────────────────────────────┐
│      Applications           │
├─────────────────────────────┤
│      Platform Services      │
├─────────────────────────────┤
│         GitOps              │
├─────────────────────────────┤
│       Kubernetes            │
├─────────────────────────────┤
│     Infrastructure          │
└─────────────────────────────┘
```

Each layer provides services to the layer above it.

---

## Infrastructure Layer

The infrastructure layer provides the resources required to run Kubernetes.

Examples include:

- Local hardware
- Virtual machines
- Cloud infrastructure
- Networking resources
- Persistent storage

Infrastructure creation is outside the scope of GitOps.

Infrastructure must exist before Kubernetes can operate.

---

## Kubernetes Layer

Kubernetes provides the execution environment for all platform services.

Responsibilities include:

- Scheduling workloads
- Service discovery
- Storage orchestration
- Network connectivity
- Resource management

Aetheric Forge currently supports:

- k3s (local development)
- Amazon EKS (cloud deployment)

---

## GitOps Layer

The GitOps layer is the heart of the platform.

Argo CD continuously reconciles the desired state stored in Git with the actual state of the cluster.

```text
Git Repository
       │
       ▼
    Argo CD
       │
       ▼
 Kubernetes
```

Changes are made through Git.

Git becomes the authoritative source of truth for platform configuration.

---

## Platform Services Layer

Platform services provide the operational capabilities required by applications.

Examples include:

- Ingress controllers
- DNS automation
- Certificate management
- Internal certificate authorities
- Load balancing
- Secret management

These services are deployed and managed through GitOps.

---

## Applications Layer

Applications represent the workloads operated by platform users.

Examples include:

- Web applications
- APIs
- Databases
- Internal services
- Educational workloads

Applications are deployed through GitOps using the same mechanisms as platform services.

---

## Ownership Model

One of the most important concepts in Aetheric Forge is ownership.

Every resource should have a clearly defined owner.

### Bootstrap-Owned

Bootstrap creates resources required before GitOps can function.

Examples:

- Repository credentials
- Initial secrets
- Environment configuration
- Cluster access configuration

Bootstrap ownership ends once GitOps becomes operational.

---

### GitOps-Owned

GitOps manages the ongoing lifecycle of platform resources.

Examples:

- Applications
- Platform services
- Certificates
- DNS records
- Ingress configuration

GitOps continuously reconciles these resources.

Manual modification is discouraged.

---

## Control Plane Services

Several platform services form the operational control plane.

```text
                Git
                 │
                 ▼
              Argo CD
                 │
 ┌───────────────┼───────────────┐
 ▼               ▼               ▼
DNS             PKI          Networking
 │               │               │
BIND         step-ca       MetalLB
ExternalDNS Cert-Manager   Ingress
```

These services work together to provide:

- Automated deployment
- Automated DNS management
- Automated certificate issuance
- Automated ingress configuration

---

## Design Goals

Aetheric Forge was designed to support:

- Reproducible deployments
- Educational environments
- Small organizational platforms
- Self-hosted infrastructure
- Incremental learning
- Minimal operational overhead

The platform favors simplicity, transparency, and repeatability over maximum flexibility.

---

## Next Steps

The remaining architecture documents explore each major subsystem in greater detail:

- [GitOps](02-bootstrap-ownership.md)
- [Networking](07-networking.md)
- [DNS](04-dns.md)
- [PKI](06-pki.md)
- [Configuration Management](05-configuration.md)
