# GitOps Architecture

GitOps is the operational foundation of Aetheric Forge.

Every major platform capability—including networking, DNS, certificate management, and application deployment—is managed through GitOps reconciliation.

Understanding GitOps is essential to understanding how the platform operates.

---

## What Is GitOps?

GitOps is an operational model in which Git becomes the authoritative source of truth for system configuration.

Rather than making changes directly within a running environment, changes are committed to a Git repository and automatically applied to the platform.

The desired state of the platform exists in Git.

The actual state of the platform exists in Kubernetes.

GitOps continuously works to make those states match.

```text
Desired State (Git)
          │
          ▼
       Argo CD
          │
          ▼
Actual State (Cluster)
```

---

## Why GitOps?

Traditional infrastructure and platform management often relies on manual changes.

Examples include:

- Editing resources with kubectl
- Making changes through web interfaces
- Executing imperative deployment commands
- Applying one-off fixes directly to running systems

These approaches create configuration drift and make environments difficult to reproduce.

GitOps addresses these challenges by ensuring that platform configuration is:

- Version controlled
- Auditable
- Reproducible
- Recoverable
- Declarative

The Git repository becomes the operational record of the platform.

---

## Core Principle

The most important rule in Aetheric Forge is:

> If a resource is managed by GitOps, modify Git instead of modifying the cluster.

Changes made directly to GitOps-managed resources are temporary.

During the next reconciliation cycle, Argo CD will restore the state defined in Git.

---

## Git as the Source of Truth

Git stores:

- Platform configuration
- Application definitions
- Infrastructure manifests
- Environment overlays
- Certificate configuration
- DNS configuration

Git does not store:

- Runtime state
- Generated secrets
- Bootstrap credentials
- Ephemeral operational data

Git describes what the platform should look like.

Git does not describe everything that happens inside the platform.

---

## Reconciliation

Reconciliation is the process of comparing the desired state with the actual state.

Argo CD continuously performs this comparison.

```text
Git Repository
       │
       ▼
Desired State
       │
       ▼
    Compare
       │
       ▼
Cluster State
```

When differences are detected, Argo CD attempts to correct them.

This process is known as self-healing.

---

## Self-Healing

Suppose an operator accidentally deletes a deployment.

```text
Git:
  deployment exists

Cluster:
  deployment missing
```

Argo CD detects the difference and recreates the deployment.

The platform automatically returns to its desired state.

This capability significantly reduces configuration drift and operational mistakes.

---

## The GitOps Control Plane

Aetheric Forge uses Argo CD as its GitOps controller.

Argo CD is responsible for:

- Monitoring Git repositories
- Detecting configuration changes
- Applying manifests
- Monitoring application health
- Restoring desired state

Argo CD acts as the bridge between Git and Kubernetes.

```text
Git
 │
 ▼
Argo CD
 │
 ▼
Kubernetes
```

---

## Application Hierarchy

Aetheric Forge organizes deployments hierarchically.

```text
Root Application
       │
       ▼
Provider Applications
       │
       ▼
Platform Components
       │
       ▼
Workloads
```

This structure allows large platforms to be managed as smaller, independent components.

Each layer is responsible for deploying the layer beneath it.

---

## Environment Management

Different environments may require different configuration.

Examples include:

- Development
- Testing
- Production

GitOps manages these differences through environment-specific overlays and configuration.

The deployment workflow remains consistent across environments.

Only configuration changes.

---

## Operational Workflow

The standard operational workflow is:

```text
Modify Configuration
         │
         ▼
Commit Changes
         │
         ▼
Push to Git
         │
         ▼
Argo CD Detects Change
         │
         ▼
Reconciliation
         │
         ▼
Updated Platform
```

No direct cluster modification is required.

---

## Failure Recovery

GitOps significantly simplifies disaster recovery.

If a cluster is lost:

1. Recreate the infrastructure.
2. Restore bootstrap credentials.
3. Restore GitOps access.
4. Allow Argo CD to reconcile the platform.

Because platform configuration already exists in Git, much of the environment can be recreated automatically.

---

## Benefits

GitOps provides several operational advantages:

- Reduced configuration drift
- Improved auditability
- Faster recovery
- Simplified change management
- Consistent deployment processes
- Reproducible environments

These characteristics make GitOps particularly well suited to educational environments, small organizations, and self-hosted infrastructure.

---

## Relationship to Bootstrap

Bootstrap and GitOps have different responsibilities.

Bootstrap creates the minimum resources required for GitOps to operate.

Examples include:

- Repository credentials
- Initial secrets
- Environment configuration
- Initial Argo CD installation

Once Argo CD becomes operational, GitOps assumes responsibility for the ongoing management of platform resources.

```text
Bootstrap
     │
     ▼
Argo CD
     │
     ▼
Platform Management
```

Bootstrap starts the platform.

GitOps runs the platform.

---

## Design Goals

The GitOps architecture in Aetheric Forge is designed to provide:

- Declarative operations
- Reproducible environments
- Automated reconciliation
- Self-healing infrastructure
- Clear ownership boundaries
- Minimal manual intervention

These goals guide every other architectural decision within the platform.

---

## Next Steps

The next document describes how deployment configuration is collected and managed within Aetheric Forge.

Continue with:

- [Configuration Management](05-configuration.md)
