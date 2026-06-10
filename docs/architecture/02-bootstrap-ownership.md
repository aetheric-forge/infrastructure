# Bootstrap Ownership

Aetheric Forge separates bootstrap responsibilities from GitOps responsibilities.

This separation is one of the most important architectural boundaries in the platform.

Bootstrap creates the minimum foundation required for GitOps to operate. After that point, GitOps becomes responsible for the ongoing management of the platform.

---

## Core Principle

The bootstrap process starts the platform.

GitOps runs the platform.

```text
Bootstrap
    │
    ▼
Argo CD
    │
    ▼
GitOps Reconciliation
    │
    ▼
Platform Management
```

Bootstrap is intentionally limited.

It should create only what is required for GitOps to become operational.

---

## Why Ownership Matters

Clear ownership prevents configuration drift, accidental overwrites, and operational confusion.

Every resource should answer a simple question:

> Who is responsible for managing this?

If the answer is unclear, the resource is likely to cause problems later.

---

## Bootstrap-Owned Resources

Bootstrap-owned resources are created before GitOps can safely manage the platform.

Examples include:

- Local environment configuration
- Initial Argo CD installation
- Git repository access credentials
- SOPS AGE key references
- Initial Kubernetes secrets required by Argo CD
- Initial DNS update credentials
- External DNS provider credentials
- Initial root application wiring

These resources exist to start reconciliation.

They are not intended to become the long-term management model for the platform.

---

## GitOps-Owned Resources

GitOps-owned resources are managed through Git and reconciled by Argo CD.

Examples include:

- Platform services
- Application definitions
- Ingress resources
- Certificate issuers
- DNS record declarations
- Environment overlays
- Service configuration
- Workload manifests

These resources should be modified in Git, not directly in the cluster.

---

## Runtime-Owned Resources

Some resources are created by controllers at runtime.

Examples include:

- Issued certificates
- Generated DNS records
- Controller-managed status fields
- Pods created by Deployments
- ReplicaSets
- Service endpoints
- Load balancer assignments

These resources are managed by Kubernetes controllers or platform controllers.

They should generally not be edited manually.

---

## Ownership Boundaries

Aetheric Forge uses three broad ownership categories:

| Owner               | Manages                     | Examples                                                 |
| ------------------- | --------------------------- | -------------------------------------------------------- |
| Bootstrap           | Initial platform foundation | Argo CD install, repository credentials, initial secrets |
| GitOps              | Desired platform state      | Applications, services, manifests, overlays              |
| Runtime Controllers | Generated operational state | Pods, certificates, DNS records, endpoints               |

Understanding these categories helps operators determine where changes should be made.

---

## Change Rules

Use the following rules:

| Resource Type             | Change Location                       |
| ------------------------- | ------------------------------------- |
| Bootstrap configuration   | Local configuration / `.env`          |
| GitOps-managed manifests  | Git                                   |
| Application configuration | Git                                   |
| Runtime status            | Do not edit directly                  |
| Generated resources       | Modify the owning declaration instead |

When in doubt, look for the owner before making changes.

---

## Example: Application Change

To change an application deployment:

1. Modify the application manifest in Git.
2. Commit the change.
3. Push to the repository.
4. Allow Argo CD to reconcile the cluster.

Do not edit the deployment directly with `kubectl`.

Manual edits will be overwritten during reconciliation.

---

## Example: Certificate Change

To change certificate behavior:

1. Modify the certificate or issuer configuration in Git.
2. Commit the change.
3. Push to the repository.
4. Allow cert-manager and Argo CD to reconcile.

Do not manually edit generated certificate secrets unless performing emergency recovery.

---

## Example: DNS Change

To change DNS behavior:

1. Modify the relevant ingress, service, or ExternalDNS configuration in Git.
2. Commit the change.
3. Push to the repository.
4. Allow Argo CD and ExternalDNS to reconcile.

Do not manually edit generated DNS records unless performing emergency repair.

---

## Bootstrap Is Not Day-Two Operations

Bootstrap is not intended to be the normal way to operate the platform.

After the platform is running, routine changes should happen through GitOps.

Bootstrap may be used again when:

- Rebuilding a cluster
- Creating a new environment
- Recovering from severe failure
- Rotating foundational credentials
- Re-establishing GitOps access

Routine platform changes should not require re-running bootstrap.

---

## Drift and Reconciliation

Configuration drift occurs when the running cluster differs from the state declared in Git.

GitOps reduces drift by continuously reconciling the cluster.

However, drift can still occur when:

- Resources are changed manually
- Secrets are rotated outside the documented process
- Runtime resources are edited directly
- Bootstrap-owned resources are modified without updating configuration

The safest correction is usually to update the owning source and allow reconciliation to complete.

---

## Design Goal

The goal of the ownership model is simple:

> Operators should always know where to make a change.

If a change belongs to bootstrap, update bootstrap configuration.

If a change belongs to GitOps, update Git.

If a resource is runtime-generated, update the declaration that creates it.

This keeps the platform predictable, reproducible, and recoverable.

---

## Next Steps

Continue with:

- [Configuration Management](05-configuration.md)
