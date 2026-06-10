# Networking Architecture

The networking layer is responsible for connecting users, services, and applications within an Aetheric Forge environment.

Its primary purpose is to ensure that traffic can be routed safely and predictably to the correct destination.

Networking works closely with DNS and PKI to provide service discovery, secure communication, and application access.

---

## Why Networking Matters

Once DNS identifies a service and PKI establishes trust, traffic must still reach the correct application.

Networking answers the question:

> How does a request reach the intended service?

```text
DNS
 │
 ▼
Where is the service?

PKI
 │
 ▼
Can the service be trusted?

Networking
 │
 ▼
How does traffic reach it?
```

Together these systems provide a complete service access model.

---

## Design Principles

The networking architecture is built around several principles:

- Services should be reachable through stable hostnames
- Traffic routing should be automated
- Internal and public access should remain distinct
- Applications should not manage networking directly
- GitOps should define networking behavior
- Platform services should provide common networking capabilities

---

## Traffic Flow

A typical request follows this path:

```text
Client
   │
   ▼
DNS
   │
   ▼
Load Balancer
   │
   ▼
Ingress Controller
   │
   ▼
Service
   │
   ▼
Application
```

Each layer has a specific responsibility.

---

## Services

Kubernetes Services provide stable network endpoints for workloads.

Applications are not accessed directly.

Instead, traffic is routed through Services.

Responsibilities include:

- Stable addressing
- Service discovery
- Load balancing between pods
- Network abstraction

Services allow applications to be replaced or scaled without affecting consumers.

---

## Ingress

Ingress resources define how external traffic enters the cluster.

Examples include:

```text
argocd.int.example.ca
grafana.int.example.ca
app.example.ca
```

Ingress resources declare:

- Hostnames
- Routing rules
- TLS configuration
- Backend services

Ingress resources describe desired behavior.

They do not process traffic directly.

---

## Ingress Controllers

Ingress controllers implement the routing behavior defined by ingress resources.

```text
Ingress
    │
    ▼
Ingress Controller
    │
    ▼
Application Service
```

Responsibilities include:

- HTTP routing
- TLS termination
- Hostname matching
- Request forwarding

The ingress controller acts as the primary entry point into the cluster.

---

## Internal and Public Access

Aetheric Forge distinguishes between internal and public traffic.

Examples of internal services include:

```text
argocd.int.example.ca
grafana.int.example.ca
```

Examples of public services include:

```text
example.ca
api.example.ca
```

Separate ingress configurations may be used to ensure traffic reaches the appropriate destination.

This separation helps maintain clear security and operational boundaries.

---

## Load Balancing

Applications often run multiple replicas.

Load balancing distributes requests across available instances.

```text
Client Requests
        │
        ▼
 Kubernetes Service
        │
        ▼
 ┌──────┼──────┐
 ▼      ▼      ▼

Pod A  Pod B  Pod C
```

This improves:

- Availability
- Scalability
- Fault tolerance

Applications can scale without changing client configuration.

---

## External Access

In local deployments, external access is typically provided through local networking infrastructure.

In cloud deployments, external access may be provided through cloud load-balancing services.

The implementation differs between deployment models.

The networking architecture remains consistent.

---

## MetalLB

Local Kubernetes environments do not normally provide load balancer functionality.

Aetheric Forge uses MetalLB to provide this capability.

```text
Client
   │
   ▼
MetalLB Address
   │
   ▼
Ingress Controller
```

MetalLB allows local deployments to behave more like cloud-hosted environments.

This provides a consistent operational experience across deployment models.

---

## Relationship to DNS

DNS and networking work together.

DNS provides discovery.

Networking provides connectivity.

```text
DNS
 │
 ▼
Hostname
 │
 ▼
Network Address
 │
 ▼
Ingress
 │
 ▼
Application
```

Without networking, DNS records would have no reachable destination.

---

## Relationship to PKI

Networking and PKI also work together.

Networking delivers traffic.

PKI protects traffic.

```text
Client
   │
   ▼
TLS Connection
   │
   ▼
Ingress
   │
   ▼
Application
```

Certificates are typically presented at the ingress layer.

This allows secure communication without requiring every application to manage certificates independently.

---

## Relationship to GitOps

Networking configuration is managed through GitOps.

Examples include:

- Services
- Ingress resources
- Load balancer configuration
- Routing rules

When networking configuration changes:

```text
Git Change
     │
     ▼
Argo CD
     │
     ▼
Networking Update
     │
     ▼
Traffic Flow Changes
```

The desired networking state remains defined in Git.

---

## Failure Recovery

Because networking configuration is declarative, it can be recreated through reconciliation.

After restoring:

- Kubernetes
- Argo CD
- Networking controllers

The desired networking configuration can be rebuilt automatically.

The authoritative source remains Git rather than manual configuration.

---

## Design Goals

The networking architecture is designed to provide:

- Predictable traffic flow
- Automated routing
- Clear access boundaries
- Consistent deployment behavior
- Scalable service access
- GitOps-managed configuration

The ultimate goal is simple:

> Applications should become reachable because they were deployed, not because someone manually configured network infrastructure.

---

## Summary

Networking provides the connectivity layer of the platform.

DNS answers:

```text
Where is the service?
```

PKI answers:

```text
Can the service be trusted?
```

Networking answers:

```text
How does traffic reach it?
```

Together these systems provide secure, discoverable, and accessible platform services.

```text
DNS
 │
 ▼
Discovery

PKI
 │
 ▼
Trust

Networking
 │
 ▼
Connectivity
```

---

## Next Steps

Continue with:

- [Secrets Management](08-secrets.md)
