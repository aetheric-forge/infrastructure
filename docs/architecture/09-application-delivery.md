# Application Delivery

Application delivery is the process of deploying workloads onto an Aetheric Forge platform.

The platform is designed so that applications are delivered through GitOps using the same principles that manage the platform itself.

Applications become part of the desired state of the environment and are continuously reconciled by the GitOps control plane.

---

## Core Principle

Applications are deployed by modifying Git.

Applications are not deployed by manually interacting with the cluster.

The standard workflow is:

```text
Application Definition
          │
          ▼
         Git
          │
          ▼
       Argo CD
          │
          ▼
     Kubernetes
          │
          ▼
    Running Service
```

Git remains the authoritative source of truth.

---

## Why GitOps Application Delivery?

Traditional deployment workflows often rely on manual commands.

Examples include:

- kubectl apply
- Helm install
- Manual configuration changes
- Direct cluster access

These approaches can introduce configuration drift and make environments difficult to reproduce.

Aetheric Forge uses GitOps to ensure applications are:

- Version controlled
- Auditable
- Reproducible
- Recoverable
- Consistent across environments

---

## Application Lifecycle

Applications follow a predictable lifecycle.

```text
Create
   │
   ▼
Commit
   │
   ▼
Deploy
   │
   ▼
Operate
   │
   ▼
Update
   │
   ▼
Retire
```

Git serves as the operational history of the application throughout this lifecycle.

---

## Application Components

Most applications consist of several Kubernetes resources.

Common examples include:

```text
Application
├── Deployment
├── Service
├── Ingress
├── ConfigMap
└── Secret
```

Each component contributes to the overall operation of the workload.

---

## Typical Application Structure

A typical application directory may contain:

```text
application/
├── deployment.yaml
├── service.yaml
├── ingress.yaml
├── configmap.yaml
├── secrets.enc.yaml
└── kustomization.yaml
```

The exact structure may vary.

The important concept is that the application is described declaratively.

Git contains the desired state.

---

## Deployments

Deployments define application workloads.

Responsibilities include:

- Container images
- Replica counts
- Resource requirements
- Environment variables
- Update strategies

Deployments describe how an application should run.

---

## Services

Services provide stable network access to workloads.

Applications are accessed through Services rather than directly through Pods.

Responsibilities include:

- Service discovery
- Stable addressing
- Load balancing
- Internal communication

Services allow workloads to scale without affecting consumers.

---

## Ingress

Ingress resources expose applications through DNS hostnames.

Examples include:

```text
app.example.ca
api.example.ca
```

Ingress resources define:

- Hostnames
- TLS requirements
- Routing rules

The networking and DNS systems automatically implement these declarations.

---

## Secrets

Applications often require sensitive configuration.

Examples include:

- Database credentials
- API tokens
- Authentication secrets

These values are typically stored as encrypted manifests.

Example:

```text
secrets.enc.yaml
```

Encrypted secrets participate in GitOps workflows while protecting sensitive information.

---

## Application Delivery Flow

A typical deployment follows this sequence:

```text
Application Manifest
          │
          ▼
       Git Commit
          │
          ▼
       Argo CD
          │
          ▼
      Deployment
          │
          ▼
        Service
          │
▼
        Ingress
           │
           ├─────────────┬─────────────┐
           ▼             ▼             ▼

        cert-manager  ExternalDNS   Ingress Controller
           │             │               │
 ▼             ▼               ▼

        Certificate   DNS Record      Routing Ready
           │             │               │
           └─────────────┴───────────────┘
                   │
                   ▼

        Application Available
          ▼
```

Several platform systems participate automatically.

The application author does not need to manually configure each layer.

---

## Relationship to DNS

Applications become discoverable through DNS.

An ingress declaration may result in:

```text
app.example.ca
```

being automatically published by ExternalDNS.

The application does not directly manage DNS records.

The platform handles this responsibility.

---

## Relationship to PKI

Applications become trusted through the certificate infrastructure.

Ingress resources may automatically trigger certificate issuance.

```text
Ingress
    │
    ▼
Certificate Request
    │
    ▼
cert-manager
    │
    ▼
Certificate
```

Applications do not typically manage certificates directly.

The platform provides this capability.

---

## Relationship to Networking

Applications consume networking services rather than implementing networking themselves.

The platform provides:

- Routing
- Load balancing
- TLS termination
- Service discovery

Application authors focus on workload behavior rather than networking implementation.

---

## Relationship to Secrets

Applications consume secrets generated or managed elsewhere.

```text
Encrypted Secret
         │
         ▼
 Kubernetes Secret
         │
         ▼
    Application
```

Applications should not contain sensitive values directly in manifests.

The platform provides mechanisms for secure secret management.

---

## Self-Healing Applications

Because applications are managed through GitOps, they benefit from reconciliation and self-healing.

If resources are modified or removed unexpectedly:

```text
Cluster Drift
      │
      ▼
   Argo CD
      │
      ▼
Reconciliation
      │
      ▼
Desired State Restored
```

This reduces operational overhead and improves platform consistency.

---

## Environment Promotion

Applications can move through environments using the same GitOps workflow.

Examples include:

```text
Development
      │
      ▼
Testing
      │
      ▼
Production
```

The promotion process remains consistent because deployments are defined declaratively.

---

## Failure Recovery

Application recovery is simplified because application definitions exist in Git.

After restoring:

- Kubernetes
- GitOps
- Platform services

Applications can be redeployed automatically through reconciliation.

The repository remains the authoritative source of truth.

---

## Design Goals

The application delivery architecture is designed to provide:

- Declarative deployments
- Automated reconciliation
- Consistent environments
- Secure service exposure
- Automated DNS integration
- Automated certificate management
- Simplified operations

The ultimate goal is simple:

> Applications should become operational because they were declared, not because they were manually deployed.

---

## Summary

Application delivery brings together every major subsystem within Aetheric Forge.

```text
GitOps
    │
    ▼
Application Definition
    │
    ▼
Deployment
    │
    ▼
Networking
    │
    ▼
DNS
    │
    ▼
PKI
    │
    ▼
Running Application
```

Every architectural component contributes to the successful delivery of applications.

This is the primary purpose of the platform.

---

## Next Steps

At this point the core architecture of Aetheric Forge has been introduced.

The remaining documentation focuses on operational workflows, platform administration, and environment-specific deployment guidance.
