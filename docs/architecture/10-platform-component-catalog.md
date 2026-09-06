# Platform Component Catalog

This catalog describes the components present in the v2.0 repository and their
owners in the Civo development reference environment.

## Substrate and bootstrap

| Component | Role | Primary owner | Important dependencies |
| --- | --- | --- | --- |
| Civo private network | Node, gateway, and private load-balancer network | Pulumi/Civo | Civo account and region |
| Civo managed k3s | Kubernetes runtime | Pulumi/Civo | Network, firewall, node pool |
| WireGuard gateway | Route between Civo and home network | Pulumi plus setup scripts | Public reachability, peer keys, forwarding |
| Kubeconfig merge | Operator cluster access | Bootstrap | Pulumi kubeconfig output, kubectl |
| Bootstrap Secrets | Initial repository, SOPS, and DNS access | Bootstrap | Operator-supplied credentials |

Local k3s and AWS EKS provide alternative substrates. MetalLB belongs to the
shared local/AWS path and is not used by the Civo reference overlay.

## Core controllers

| Component | Role | Managed by | Dependencies |
| --- | --- | --- | --- |
| ingress-nginx private | Internal HTTP routing and TLS termination | Kubernetes manifests/Helm | Civo private firewall and load balancer |
| ingress-nginx public | Public HTTP routing and TLS termination | Kubernetes manifests/Helm | Civo public load balancer |
| ExternalDNS internal | RFC2136 publication of internal names | Kubernetes manifests/Helm | BIND, TSIG, WireGuard route |
| ExternalDNS public | Cloudflare publication of public names | Kubernetes manifests/Helm | Cloudflare token and public zone |
| cert-manager | Public/private certificate lifecycle | Kubernetes manifests | DNS, issuers, step-ca trust |
| step-ca | Private CA and ACME endpoint | Kubernetes manifests | Encrypted CA material, internal DNS |
| Velero | Backup orchestration | Kubernetes manifests | MinIO S3 endpoint and credentials |

Pi-hole and BIND are external to the reference cluster. Pi-hole provides client
resolution on port 53; BIND provides internal authority and RFC2136 on port
5335.

## Operators

| Operator | Owns |
| --- | --- |
| MinIO Operator | MinIO Tenant and storage workloads |
| CloudNativePG | PostgreSQL cluster, Pods, and managed Services |
| MongoDB Community Operator | MongoDB replica set and supporting workloads |
| Keycloak Operator | Keycloak deployment and Service |
| RabbitMQ Cluster Operator | RabbitMQ cluster and Service |

Operator-created children must be configured through their custom resources or
supported templates. Direct child edits are subject to reconciliation.

## Shared services

| Service | Purpose | Exposure in Civo dev | Major dependencies |
| --- | --- | --- | --- |
| Argo CD | GitOps UI and reconciliation engine | Private ingress | Git repository key, SOPS identity, step-ca TLS |
| Keycloak | Identity provider and SSO | Public ingress | PostgreSQL, public DNS and ACME |
| MinIO | Object storage and console | Private ingress | MinIO Operator, storage, Keycloak OIDC |
| PostgreSQL | Relational data and Keycloak database | Cluster plus private load balancer | CloudNativePG, storage, private DNS |
| MongoDB | Document database | Private load balancer | MongoDB Operator, storage, private DNS |
| RabbitMQ | Messaging and management | Private load balancer/ingress as declared | RabbitMQ Operator, storage, private DNS |
| Redis | Cache and coordination | ClusterIP | Storage and encrypted authentication Secret |

The `minio-admins` policy is declarative and grants the administrative, KMS,
and S3 permissions required for MinIO console administration through SSO.

## External systems

| System | Responsibility |
| --- | --- |
| Cloudflare | Public DNS authority and records |
| Pi-hole | Private client resolver and conditional forwarder |
| BIND | Internal zone authority, RFC2136, ACME TXT records |
| Git provider | Desired-state repository and deploy-key authorization |
| Pulumi backend | Infrastructure state and update history |
| Home router | LAN routing, WireGuard peer, forwarding, persistent firewall/NAT |
| Client trust stores | Trust of the private step-ca root |

These are real platform dependencies even though their complete configuration
does not live in this repository.

## Dependency summary

```text
Cloud infrastructure
        │
        ▼
Kubernetes + WireGuard route
        │
        ├──► DNS ──► PKI ──► ingress
        │
        ├──► operators ──► stateful services
        │
        └──► repository/SOPS access ──► desired configuration
```

Failures should be diagnosed from the earliest dependency boundary. A service
cannot repair a missing route; a certificate cannot repair stale authoritative
DNS; and Argo CD cannot reconcile external state it does not own.

## Release status

All components listed above are implemented in the repository. The complete
end-to-end validation claim applies to the Civo `dev` overlay for v2.0. Local
k3s and AWS assets remain available with narrower validation, while `test` and
`prod` are not complete operational environments.
