# DNS Architecture

DNS is a foundational component of the Aetheric Forge control plane.

Rather than treating DNS as a separate operational concern, Aetheric Forge integrates DNS directly into the GitOps platform architecture.

This enables automated service discovery, ingress publication, certificate issuance, and platform self-management.

---

## Why DNS Matters

Many platform services depend on reliable DNS.

Examples include:

- Argo CD ingress
- Application ingress
- Certificate validation
- Service discovery
- Platform APIs

Without DNS, users and systems must rely on direct IP addressing, which becomes difficult to manage as environments grow.

Aetheric Forge uses automated DNS management to ensure that platform resources remain discoverable and consistent.

---

## Design Principles

The DNS architecture is built around several principles:

- DNS is part of the control plane
- DNS records are generated automatically
- Platform services should not require manual DNS administration
- Internal and public DNS responsibilities remain separate
- GitOps defines desired DNS behavior

---

## DNS Ownership

DNS management is distributed across several components.

```text
Ingress
    │
    ▼
ExternalDNS
    │
    ▼
DNS Provider
    │
    ▼
DNS Records
```

Applications and platform services declare their networking requirements.

ExternalDNS converts those requirements into DNS records.

The authoritative DNS server remains responsible for publishing those records.

---

## Internal DNS

Internal DNS provides name resolution for services intended to remain inside the platform or private network.

Examples include:

- Internal Argo CD access
- Administrative services
- Internal APIs
- Platform management interfaces

The local deployment model uses BIND9 as the authoritative internal DNS server.

```text
Applications
      │
      ▼
Ingress
      │
      ▼
ExternalDNS
      │
      ▼
RFC2136 Updates
      │
      ▼
BIND9
```

ExternalDNS performs authenticated dynamic updates using RFC2136 and TSIG credentials.

---

## Public DNS

Public DNS provides name resolution for services intended to be reachable from external networks.

Examples include:

- Public websites
- Public APIs
- Internet-facing applications

Public DNS records are managed through supported DNS providers.

Examples include:

- Cloudflare
- Route53
- Other supported providers

ExternalDNS publishes records using provider-specific APIs.

```text
Applications
      │
      ▼
Ingress
      │
      ▼
ExternalDNS
      │
      ▼
Provider API
      │
      ▼
Public DNS
```

---

## DNS Automation

DNS records are not typically created manually.

Instead, records are generated automatically from platform resources.

For example:

```text
Ingress Created
        │
        ▼
ExternalDNS Detects Hostname
        │
        ▼
DNS Record Created
```

Removing the resource causes the DNS record to be removed automatically.

This ensures that DNS remains synchronized with the actual state of the platform.

---

## RFC2136 Integration

Local deployments use RFC2136 dynamic updates to communicate with BIND9.

RFC2136 provides:

- Authenticated updates
- Automated record management
- Controller-driven reconciliation

Authentication is performed using TSIG credentials configured during bootstrap.

```text
ExternalDNS
      │
      ▼
TSIG Authentication
      │
      ▼
RFC2136 Update
      │
      ▼
BIND9
```

This allows DNS records to be managed automatically without granting unrestricted administrative access to the DNS server.

---

## ExternalDNS

ExternalDNS acts as the DNS reconciliation controller.

Its responsibilities include:

- Monitoring Kubernetes resources
- Generating DNS records
- Creating records
- Updating records
- Removing obsolete records

ExternalDNS performs for DNS what Argo CD performs for Kubernetes resources.

```text
Desired DNS State
         │
         ▼
    ExternalDNS
         │
         ▼
Authoritative DNS
```

---

## DNS and GitOps

DNS configuration is ultimately driven by GitOps.

When a service is added, modified, or removed through Git, the platform automatically updates DNS to match.

```text
Git Change
     │
     ▼
Argo CD
     │
     ▼
Ingress Update
     │
     ▼
ExternalDNS
     │
     ▼
DNS Update
```

This creates a fully automated workflow from configuration change to published DNS record.

---

## Zone Authority Boundaries

Aetheric Forge separates internal and public DNS by delegating authority to different DNS zones.

Example:

```text
Public Zone

    example.ca

Internal Zone

    int.example.ca
```

These zones are managed independently.

The internal DNS server is authoritative only for the internal zone.

The public DNS provider is authoritative only for the public zone.

```text
                    DNS
                     │
        ┌────────────┴────────────┐
        ▼                         ▼

   example.ca              int.example.ca
   Public Zone             Internal Zone

   Cloudflare                 BIND9
```

This architecture intentionally avoids split-horizon DNS.

In a split-horizon design, the same DNS zone returns different answers depending on the source of the query.

For example:

```text
example.ca

    Internal Query → 10.0.0.5
    External Query → 203.0.113.10
```

Aetheric Forge does not use this model.

Instead, internal and external resources receive distinct hostnames within separate authoritative zones.

Examples:

```text
argocd.example.ca
argocd.int.example.ca
```

This approach provides:

- Clear authority boundaries
- Simpler troubleshooting
- Predictable resolution behavior
- Reduced DNS ambiguity
- Easier disaster recovery

A hostname should resolve identically regardless of where the query originates.

The hostname itself communicates whether the resource is intended for internal or public access.

---

## Internal and Public Separation

Aetheric Forge intentionally separates internal and public DNS responsibilities.

```text
                 DNS
                  │
       ┌──────────┴──────────┐
       ▼                     ▼

 Internal Zone         Public Zone
 int.example.ca         example.ca

     BIND9             DNS Provider
       │                    │
       ▼                    ▼

 Internal Services    Public Services
```

This separation provides:

- Improved security
- Reduced accidental exposure
- Clear operational boundaries
- Simplified troubleshooting

Internal resources remain private unless intentionally published through the public zone.

This model encourages explicit exposure decisions rather than relying on network location or DNS query origin.

A service should be public because it was intentionally published, not because DNS returned a different answer.

The DNS namespace itself communicates the intended visibility of the service.

---

## Failure Recovery

Because DNS configuration is driven by platform configuration rather than manual record creation, recovery is simplified.

After restoring:

- Kubernetes
- Argo CD
- ExternalDNS
- DNS credentials

DNS records can be recreated automatically through reconciliation.

The authoritative source remains the platform configuration rather than manually maintained DNS entries.

---

## Design Goals

The DNS architecture is designed to provide:

- Automated DNS management
- GitOps-driven reconciliation
- Clear authority boundaries
- Secure dynamic updates
- Consistent service discovery
- Minimal manual administration

The ultimate goal is simple:

> Services should become reachable because they were deployed, not because someone manually created a DNS record.

---

## Next Steps

Continue with:

- [PKI Architecture](06-pki.md)
