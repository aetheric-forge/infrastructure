# Platform Component Catalog

## Purpose

This document defines the components that comprise the Aetheric Forge GitOps Bootstrap platform, their responsibilities, ownership boundaries, and dependencies.

The catalog serves as the authoritative inventory of platform services and is used to guide operational decisions, architecture reviews, platform evolution, and future service integration.

The objective is not to describe implementation details, but rather to provide a clear understanding of what components exist within the platform and the role each component plays.

---

# Component Classification

Platform components are organized into the following layers:

| Layer     | Purpose                                                                   |
| --------- | ------------------------------------------------------------------------- |
| Substrate | Physical and virtual resources required to host the platform              |
| Bootstrap | Services required to establish GitOps control and platform administration |
| Platform  | Shared cluster services consumed by workloads                             |
| Workloads | Applications and services deployed onto the platform                      |

These classifications help establish ownership boundaries and clarify responsibility throughout the platform lifecycle.

---

# Substrate Layer

## Kubernetes

| Property     | Value                            |
| ------------ | -------------------------------- |
| Component    | Kubernetes                       |
| Role         | Container orchestration platform |
| Owner        | Infrastructure                   |
| Managed By   | Pulumi                           |
| Dependencies | Compute, networking, storage     |

### Responsibilities

- Cluster scheduling
- Container orchestration
- Service networking
- Storage integration
- Kubernetes API services

---

# Bootstrap Layer

## Argo CD

| Property     | Value                        |
| ------------ | ---------------------------- |
| Component    | Argo CD                      |
| Role         | GitOps reconciliation engine |
| Owner        | Platform                     |
| Managed By   | Bootstrap process            |
| Dependencies | Kubernetes, Git repository   |

### Responsibilities

- Declarative deployment management
- Continuous reconciliation
- Drift detection
- Application lifecycle management

### Notes

Argo CD serves as the platform control plane and is responsible for managing all GitOps-controlled resources following bootstrap completion.

---

## WireGuard

| Property     | Value                 |
| ------------ | --------------------- |
| Component    | WireGuard             |
| Role         | Administrative access |
| Owner        | Bootstrap             |
| Managed By   | Bootstrap process     |
| Dependencies | Network connectivity  |

### Responsibilities

- Secure administrative access
- Bootstrap connectivity
- Platform management access

### Notes

WireGuard provides private administrative access to platform services and is intended to reduce reliance on publicly exposed management endpoints.

---

# Platform Layer

## BIND

| Property     | Value               |
| ------------ | ------------------- |
| Component    | BIND                |
| Role         | DNS services        |
| Owner        | Platform            |
| Managed By   | Argo CD             |
| Dependencies | Kubernetes, MetalLB |

### Responsibilities

- Internal DNS resolution
- Zone management
- Service discovery support

---

## step-ca

| Property     | Value                 |
| ------------ | --------------------- |
| Component    | step-ca               |
| Role         | Certificate Authority |
| Owner        | Platform              |
| Managed By   | Argo CD               |
| Dependencies | DNS                   |

### Responsibilities

- Internal PKI
- Certificate issuance
- ACME services
- Trust establishment

---

## MetalLB

| Property     | Value                 |
| ------------ | --------------------- |
| Component    | MetalLB               |
| Role         | Load balancing        |
| Owner        | Platform              |
| Managed By   | Argo CD               |
| Dependencies | Kubernetes networking |

### Responsibilities

- LoadBalancer service support
- Address allocation
- Service exposure

---

## Ingress Controller

| Property     | Value                    |
| ------------ | ------------------------ |
| Component    | NGINX Ingress Controller |
| Role         | HTTP ingress and routing |
| Owner        | Platform                 |
| Managed By   | Argo CD                  |
| Dependencies | MetalLB, step-ca         |

### Responsibilities

- HTTP routing
- TLS termination
- Application exposure
- Ingress policy enforcement

---

## ExternalDNS

| Property     | Value          |
| ------------ | -------------- |
| Component    | ExternalDNS    |
| Role         | DNS automation |
| Owner        | Platform       |
| Managed By   | Argo CD        |
| Dependencies | BIND           |

### Responsibilities

- DNS record management
- Service-to-DNS reconciliation
- Automated platform naming

---

## cert-manager

| Property     | Value                            |
| ------------ | -------------------------------- |
| Component    | cert-manager                     |
| Role         | Certificate lifecycle management |
| Owner        | Platform                         |
| Managed By   | Argo CD                          |
| Dependencies | step-ca                          |

### Responsibilities

- Certificate provisioning
- Certificate renewal
- Integration with ACME issuers

---

## Keycloak

| Property     | Value                          |
| ------------ | ------------------------------ |
| Component    | Keycloak                       |
| Role         | Identity and access management |
| Owner        | Platform                       |
| Managed By   | Argo CD                        |
| Dependencies | DNS, step-ca                   |

### Responsibilities

- Authentication
- Authorization
- Single Sign-On (SSO)
- OIDC federation
- Identity management

### Notes

The Keycloak operator (`platform/operators/keycloak`) manages the Keycloak instance lifecycle; the running realm/service configuration lives in `platform/services/forge-keycloak`.

---

## CloudNativePG

| Property     | Value                        |
| ------------ | ----------------------------- |
| Component    | CloudNativePG                 |
| Role         | PostgreSQL operator            |
| Owner        | Platform                       |
| Managed By   | Argo CD                        |
| Dependencies | Kubernetes                     |

### Responsibilities

- PostgreSQL cluster provisioning
- Backup and recovery orchestration
- Database lifecycle management for platform and workload services

### Notes

The operator (`platform/operators/cnpg`) provisions the engine; `platform/services/forge-db` defines the application-facing Postgres cluster and its nightly backup schedule.

---

## MinIO

| Property     | Value               |
| ------------ | -------------------- |
| Component    | MinIO                 |
| Role         | S3-compatible object storage |
| Owner        | Platform              |
| Managed By   | Argo CD                |
| Dependencies | Kubernetes, storage     |

### Responsibilities

- S3-compatible object storage
- Bucket provisioning for platform and workload services

### Notes

Split across `platform/operators/minio` (operator) and `platform/services/minio` (tenant/instance configuration).

---

## SeaweedFS

| Property     | Value               |
| ------------ | -------------------- |
| Component    | SeaweedFS             |
| Role         | Distributed object/file storage |
| Owner        | Platform              |
| Managed By   | Argo CD                |
| Dependencies | Kubernetes, storage     |

### Responsibilities

- Distributed storage backend for platform data services

---

## Velero

| Property     | Value                 |
| ------------ | ---------------------- |
| Component    | Velero                  |
| Role         | Backup and disaster recovery |
| Owner        | Platform                 |
| Managed By   | Argo CD (post-bootstrap)  |
| Dependencies | Kubernetes, object storage |

### Responsibilities

- Cluster resource and volume backups
- Disaster recovery restore workflows

---

# Workload Layer

## Redis

| Property  | Value                     |
| --------- | -------------------------- |
| Component | Redis                       |
| Managed By| Argo CD (`platform/services/redis`) |

### Responsibilities

- Caching
- Session storage
- Distributed coordination

---

## RabbitMQ

| Property  | Value                      |
| --------- | --------------------------- |
| Component | RabbitMQ                     |
| Managed By| Argo CD (`platform/operators/rabbitmq`, `platform/services/rabbitmq`) |

### Responsibilities

- Messaging
- Event distribution
- Work queue management

---

## MongoDB

| Property  | Value                        |
| --------- | ------------------------------ |
| Component | MongoDB                         |
| Managed By| Argo CD (`platform/operators/forge-mongo`, `platform/services/forge-mongo`) |

### Responsibilities

- Document persistence
- Application data storage

---

# Ownership Boundaries

The platform is intentionally divided into ownership layers.

| Layer          | Responsibility                                                |
| -------------- | ------------------------------------------------------------- |
| Infrastructure | Provisioning and lifecycle management of Kubernetes resources |
| Bootstrap      | Initial platform establishment and administrative access      |
| Platform       | Shared services required by workloads                         |
| Workloads      | Business and application services                             |

Ownership boundaries are intended to minimize operational ambiguity and clarify lifecycle responsibilities.

---

# Dependency Summary

| Component          | Depends On            |
| ------------------ | ---------------------- |
| Argo CD            | Kubernetes            |
| WireGuard          | Network connectivity  |
| BIND               | Kubernetes, MetalLB   |
| step-ca            | DNS                   |
| cert-manager       | step-ca               |
| ExternalDNS        | BIND                  |
| Ingress Controller | MetalLB, step-ca      |
| Keycloak           | DNS, step-ca          |
| CloudNativePG      | Kubernetes            |
| MinIO              | Kubernetes, storage   |
| SeaweedFS          | Kubernetes, storage   |
| Velero             | Kubernetes, object storage |
| Redis              | Kubernetes            |
| RabbitMQ           | Kubernetes            |
| MongoDB            | Kubernetes            |

---

# Platform Evolution

| Version | Milestone                                                           |
| ------- | --------------------------------------------------------------------- |
| v0.8.0  | Bootstrap platform baseline                                           |
| v0.8.1  | Identity integration and federation (Keycloak)                        |
| v0.8.2  | Data and storage services (CloudNativePG, MinIO, SeaweedFS, Velero)   |
| v0.9.0  | Application services layer (Redis, RabbitMQ, MongoDB)                 |
| current | Production GKE cluster live end to end                                |

This catalog will evolve as platform services are added, removed, or reassigned between ownership layers.
