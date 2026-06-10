# PKI Architecture

Public Key Infrastructure (PKI) provides identity and trust within an Aetheric Forge environment.

While DNS allows systems to locate services, PKI allows systems to verify that those services are authentic.

Together, DNS and PKI form the foundation of secure service communication.

---

## Why PKI Matters

When a user connects to a service, two questions must be answered:

1. Where is the service?
2. Can the service be trusted?

DNS answers the first question.

PKI answers the second.

```text
DNS
 │
 ▼
Where is the service?

PKI
 │
 ▼
Can the service be trusted?
```

Without PKI, encrypted communication cannot reliably verify the identity of the systems involved.

---

## Design Principles

The PKI architecture is built around several principles:

- Trust should be automated
- Certificate issuance should not require manual intervention
- Internal and external trust domains should remain separate
- Certificates should be managed declaratively
- Renewal should occur automatically
- GitOps should define desired certificate behavior

---

## Architectural Components

Several components work together to provide certificate management.

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
Certificate Authority
    │
    ▼
Issued Certificate
```

Each component has a specific responsibility.

---

## Certificate Authority

A Certificate Authority (CA) is responsible for issuing certificates.

Within Aetheric Forge, the internal certificate authority serves as the trust anchor for internal services.

The CA establishes:

- Service identity
- Certificate issuance policy
- Trust relationships
- Renewal authority

The CA becomes the source of trust for internal platform communication.

---

## Internal Trust Domain

Aetheric Forge maintains an internal trust domain separate from public certificate infrastructure.

Examples include:

```text
argocd.int.example.ca
grafana.int.example.ca
api.int.example.ca
```

Certificates for these services are issued by the internal certificate authority.

```text
Internal Service
       │
       ▼
Internal CA
       │
       ▼
Internal Certificate
```

This allows internal services to operate independently of public certificate providers.

---

## Public Trust Domain

Public services may require certificates trusted by external clients.

Examples include:

```text
example.ca
api.example.ca
app.example.ca
```

These services may use publicly trusted certificate authorities.

```text
Public Service
       │
       ▼
Public CA
       │
       ▼
Public Certificate
```

The specific public CA depends on deployment requirements.

---

## Certificate Automation

Aetheric Forge automates certificate lifecycle management.

The platform automatically:

- Requests certificates
- Issues certificates
- Renews certificates
- Replaces expiring certificates

Operators should rarely need to manage certificates manually.

---

## cert-manager

cert-manager acts as the certificate lifecycle controller.

Its responsibilities include:

- Monitoring certificate resources
- Requesting certificates
- Managing renewals
- Tracking certificate status
- Updating certificate secrets

cert-manager performs for certificates what ExternalDNS performs for DNS records.

```text
Desired Certificate State
             │
             ▼
        cert-manager
             │
             ▼
   Certificate Authority
```

---

## step-ca

Aetheric Forge uses step-ca as the internal certificate authority.

step-ca provides:

- Internal certificate issuance
- ACME compatibility
- Automated renewal support
- Internal trust management

```text
cert-manager
      │
      ▼
   ACME
      │
      ▼
 step-ca
      │
      ▼
Certificate
```

This allows internal certificates to be issued using the same operational model commonly used with public certificate authorities.

---

## ACME

ACME provides a standard protocol for automated certificate issuance.

Aetheric Forge uses ACME internally to simplify certificate management.

Benefits include:

- Standardized workflows
- Automated issuance
- Automated renewal
- Reduced operational complexity

Applications do not need to understand the underlying certificate authority.

They simply request certificates through the platform.

---

## Relationship to GitOps

Certificate behavior is defined through GitOps-managed resources.

Examples include:

- Issuers
- ClusterIssuers
- Certificates
- Ingress resources

When GitOps applies a change:

```text
Git Change
     │
     ▼
Argo CD
     │
     ▼
cert-manager
     │
     ▼
Certificate Issued
```

The desired certificate state remains stored in Git.

The actual certificate lifecycle is managed by platform controllers.

---

## Runtime Ownership

Certificates are examples of runtime-generated resources.

GitOps defines:

- What certificates should exist
- Which authority should issue them
- Which services should use them

Runtime controllers generate:

- Certificate requests
- Issued certificates
- Renewal operations
- Certificate secrets

This separation follows the ownership principles described elsewhere in the architecture.

---

## Failure Recovery

Because certificate configuration is managed declaratively, recovery is simplified.

After restoring:

- Kubernetes
- GitOps
- cert-manager
- step-ca

Certificates can be recreated automatically through reconciliation.

The platform configuration remains the authoritative source of truth.

---

## Design Goals

The PKI architecture is designed to provide:

- Automated trust management
- Declarative certificate configuration
- Internal certificate authority support
- Automated renewal
- GitOps-driven operations
- Minimal manual intervention

The ultimate goal is simple:

> Services should receive trusted certificates because they were deployed, not because someone manually generated them.

---

## Summary

PKI provides the trust layer of the Aetheric Forge platform.

DNS answers:

```text
Where is the service?
```

PKI answers:

```text
Can the service be trusted?
```

Together they provide secure, automated service discovery and communication.

```text
DNS
 │
 ▼
Location

PKI
 │
 ▼
Trust
```

---

## Next Steps

Continue with:

- [Networking Architecture](07-networking.md)
