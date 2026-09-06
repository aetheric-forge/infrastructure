# Deployment Models

Aetheric Forge Infrastructure contains several deployment paths, but they do
not have equal scope or validation. In v2.0, the Civo development environment
is the reference deployment.

Choose a model according to what you need to operate, not simply where you want
to run containers.

## Model summary

| Model | Infrastructure | Kubernetes | Platform bootstrap | v2.0 status |
| --- | --- | --- | --- | --- |
| Civo development | Created by Pulumi | Civo managed k3s | Civo `dev` overlay | Reference and fully exercised |
| Local development | Supplied by the operator | Existing local k3s | Shared `dev` overlay | Supported, not fully revalidated for v2.0 |
| AWS development | Created by Pulumi | Amazon EKS | Shared `dev` overlay | Supported legacy cloud path |
| Docker Compose | Supplied by the operator | Not used | Not used | Separate application-development stack |

The repository also contains `test` and `prod` manifests. They are not complete
v2.0 reference environments and should not be presented or operated as such
without additional validation.

## Civo development

Civo is the recommended model for deploying the complete v2.0 development
platform.

Pulumi creates:

- A dedicated Civo private network
- A managed k3s cluster and node pool
- Cluster and private load-balancer firewalls
- A WireGuard gateway when WireGuard is enabled

The Civo-specific `dev` overlay then deploys the platform in four layers:

1. Core controllers
2. Platform configuration
3. Operators and their custom resources
4. Shared platform services

### Networking model

The reference environment uses separate public and private ingress-nginx
controllers. Public applications use the public ingress load balancer. Internal
web applications and the MinIO S3 endpoint use the private ingress load
balancer.

Private non-HTTP services receive dedicated Civo load balancers. During
deployment, the bootstrap workflow discovers their private addresses and
publishes those addresses through internal DNS. Kubernetes Service status may
contain a publicly routable address and is not treated as the internal DNS
target.

The Civo VPC reaches the home DNS and private network through WireGuard. This
route is part of the reference architecture rather than an optional
administrative convenience: internal DNS updates, private ACME validation, and
access from the home network depend on it.

### Operational boundaries

- The exercised environment is `clusters/single/civo/dev`.
- Private load-balancer address discovery occurs during deployment; it is not a
  continuously running controller.
- Replacing a load balancer requires the affected deployment stage to be rerun
  so its private DNS target can be rediscovered.
- The internal DNS service is external to the cluster in the reference
  environment.
- Clean-room disaster recovery is not yet automated end to end.

For the private service publication workflow, see
[Civo dev private service DNS](../clusters/single/civo/dev/README.md).

## Local development with k3s

The local model applies the shared `dev` overlay to an existing k3s cluster. It
is useful for platform development, laboratories, and environments where the
operator already owns the host and network.

The repository does not provision the local machine or install k3s. The
operator must provide:

- A working k3s cluster and kubeconfig
- LoadBalancer support suitable for the local network
- An authoritative internal DNS service with RFC2136 updates
- The routes, firewall policy, and trust configuration required by that network

The shared overlay includes MetalLB-oriented configuration that is not used by
the Civo reference environment.

### Operational boundaries

- Local host provisioning is outside Pulumi's scope.
- Network addresses and DNS delegation depend on the operator's LAN.
- The local path has not received the same complete v2.0 validation as Civo.
- WireGuard should be configured only when the local topology requires it; it
  is not needed merely to reach a cluster on the same host or LAN.

See [Local k3s](local/k3s.md) and [Local BIND9](local/bind9.md) for the existing
host preparation notes. Those guides are scheduled for a v2.0 accuracy pass.

## AWS development with EKS

The AWS model provisions an AWS network foundation and Amazon EKS cluster with
Pulumi. It retains the original cloud deployment path that predates the Civo
reference environment.

The foundation project can create:

- A VPC and subnets
- Internal DNS infrastructure
- A WireGuard gateway and its security group when enabled

The cluster project creates EKS resources and installs AWS-specific supporting
components such as the EBS CSI driver and cluster autoscaler. Platform
bootstrap uses the shared `dev` overlay rather than the Civo-specific overlay.

### Operational boundaries

- AWS remains implemented but is not the reference environment for v2.0.
- AWS-specific credentials, DNS ownership, routing, and IAM configuration are
  required.
- Operators should run a clean preview and deployment validation before relying
  on the path for a new environment.
- Civo-specific private load-balancer discovery and service-field adoption do
  not apply to AWS.

## Docker Compose development

The Docker Compose project is not a Kubernetes deployment model and does not
provision cloud infrastructure. It runs shared application dependencies for
local Aetheric Forge and Black Circuit development.

The stack includes local instances of:

- Keycloak
- MinIO
- MongoDB
- PostgreSQL
- RabbitMQ
- Redis
- Aetheric Forge and Black Circuit web applications

Use this model when working on applications without needing the Kubernetes
control plane, GitOps reconciliation, cloud load balancers, or the private
network architecture.

See the [Docker development guide](../docker/README.md).

## Test and production manifests

The repository contains `clusters/single/test` and `clusters/single/prod`
content, but neither is declared as a complete supported v2.0 deployment model.

- `test` contains bootstrap and GitOps overlays useful for platform testing.
- `prod` contains initial production-oriented namespace and overlay structure.

Treat these as development assets. Before promoting either to an operational
environment, define and validate its infrastructure, networking, DNS, PKI,
secrets, backup, monitoring, and recovery requirements.

## Choosing a model

Use the following defaults:

| Goal | Recommended model |
| --- | --- |
| Deploy the complete v2.0 development platform | Civo development |
| Develop or study platform manifests on owned hardware | Local k3s |
| Maintain or evaluate the existing AWS path | AWS development |
| Run application dependencies without Kubernetes | Docker Compose |
| Operate a production platform | Define and validate a production design first |

After selecting a model, continue to [Prerequisites](00-prerequisites.md) and
the [Quick Start](01-quickstart.md). Both guides identify the Civo path as the
v2.0 reference and call out provider-specific requirements.
