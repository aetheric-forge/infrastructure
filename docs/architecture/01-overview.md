# Architecture Overview

Aetheric Forge Infrastructure builds a Kubernetes platform in layers with an
explicit owner for each kind of state. The v2.0 reference environment is the
Civo `dev` deployment; local k3s and AWS use related but different substrate and
networking implementations.

## Architectural layers

```text
Applications and clients
          │
          ▼
Shared platform services
          │
          ▼
Controllers and operators
          │
          ▼
Kubernetes cluster
          │
          ▼
Cloud or local infrastructure
```

### Infrastructure

Infrastructure supplies compute, networks, firewalls, load balancers, and
storage. Pulumi creates the Civo and AWS infrastructure. A local deployment
uses an existing operator-managed host and k3s cluster.

### Kubernetes

The repository supports:

- Civo managed k3s as the v2.0 reference
- An existing local k3s cluster
- Amazon EKS as the retained AWS path

Kubernetes owns scheduling, Service networking, storage attachment, and the
runtime objects created by controllers.

### Controllers and operators

Controllers provide shared control-plane behavior:

- Public and private ingress-nginx
- Public and internal ExternalDNS
- cert-manager and step-ca
- Velero
- MinIO, CloudNativePG, MongoDB Community, Keycloak, and RabbitMQ operators

### Shared services

The development platform includes Argo CD, Keycloak, MinIO, RabbitMQ,
PostgreSQL, MongoDB, and Redis. Their desired definitions live under
`platform/` and are assembled by environment overlays under `clusters/`.

## Reference traffic paths

```text
Internet ──► public Civo load balancer ──► nginx-public ──► public ingress

Private client ──► private network/WireGuard
                         │
                         ├──► private Civo load balancer ──► nginx-private
                         └──► dedicated private service load balancers

Cluster ──► WireGuard gateway ──► home DNS network
                                      │
                         ┌────────────┴────────────┐
                         ▼                         ▼
                   Pi-hole :53                BIND :5335
                  client resolver      authority and RFC2136
```

Public DNS is published through Cloudflare. Internal records are published to
BIND using authenticated RFC2136 updates. Pi-hole answers ordinary client
queries and forwards the internal zone to BIND.

Private certificates are issued by step-ca through cert-manager. Public
certificates use the public ACME issuer. Internal DNS-01 checks and updates go
directly to BIND on port 5335 to avoid resolver negative caching.

## Ownership model

| Owner | State |
| --- | --- |
| Pulumi | Cloud networks, compute, clusters, firewalls, and gateway resources |
| Bootstrap scripts | Initial access, generated values, staged manifest application, and trust wiring |
| Version-controlled manifests | Desired controller, operator, and service definitions |
| Runtime controllers | Pods, endpoints, load-balancer assignments, DNS records, and certificates |
| External operators | Cloud accounts, DNS zones, home routing, trust stores, and recovery keys |

The owner determines where a change belongs. For example, a Civo firewall is
changed in Pulumi, an ingress hostname in its manifest, and an issued
Certificate is repaired by fixing its Certificate or issuer declaration.

## Bootstrap sequence

The reference bootstrap proceeds in dependency order:

1. Foundation Pulumi project
2. Civo network, cluster, firewalls, and WireGuard gateway
3. Kubeconfig and bootstrap secrets
4. WireGuard connection to the home network
5. Core controllers
6. Provider and platform configuration
7. Operators and CRDs
8. Shared services and private-address discovery
9. step-ca trust wiring and validation

The Civo service phase uses two passes. It first creates private load balancers
without publishing unsafe targets, discovers their private addresses, then
reapplies their owning resources with internal DNS publication enabled.

## Design boundaries

- Civo `dev` is the fully exercised v2.0 environment.
- Internal DNS and the home-side WireGuard router are external dependencies.
- Private Civo load-balancer discovery runs during deployment, not continuously.
- `test` and `prod` manifests are development assets, not complete supported
  environments.
- SOPS-encrypted manifests may be tracked; plaintext secrets and generated
  local state may not.
- Clean-room disaster recovery is not yet automated end to end.

## Next steps

- [Bootstrap Ownership](02-bootstrap-ownership.md)
- [GitOps](03-gitops.md)
- [DNS](04-dns.md)
- [PKI](06-pki.md)
- [Networking](07-networking.md)
