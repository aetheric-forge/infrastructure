# Application Delivery

Application delivery combines a version-controlled workload declaration with
network visibility, DNS, certificates, configuration, and secrets. An
application is ready only when every required controller boundary has
reconciled.

## Workload structure

Reusable application or service definitions belong in a base. Provider and
environment differences belong in overlays:

```text
component/
├── base/
│   ├── deployment-or-operator-resource.yaml
│   ├── service.yaml
│   └── kustomization.yaml
├── overlays/
│   └── dev/
└── secrets/
    └── dev/
        └── secret.enc.yaml
```

The exact structure varies for operator-managed services, but ownership should
remain visible.

## Delivery chain

```text
Manifest/overlay
      │
      ├──► workload controller ──► ready Pods
      ├──► Service ──────────────► endpoints/load balancer
      ├──► Ingress ──────────────► nginx routing
      ├──► ExternalDNS ──────────► public or internal record
      └──► cert-manager ─────────► TLS Secret
```

A healthy Deployment does not prove that DNS, TLS, or ingress works. Conversely,
a valid DNS record can point to an unhealthy or unintended load balancer.

## Public and private exposure

An exposed HTTP application must align three declarations:

| Concern | Public | Private |
| --- | --- | --- |
| Ingress class | `nginx-public` | `nginx-private` |
| DNS zone | External domain | Internal domain |
| Certificate issuer | Public ACME | step-ca internal ACME |

Public exposure is an explicit design decision. Moving a hostname between zones
without changing ingress and certificate policy creates a broken or unsafe
deployment.

## Protocol services

Non-HTTP services can use ClusterIP for cluster-only access or a private
LoadBalancer Service for routed clients. In Civo, internal DNS for dedicated
load balancers uses validated private provider addresses, not the public Service
status address.

Operator-managed services must declare annotations and additional Services in
the owning custom resource when the operator reconciles those children.

## Configuration and secrets

Non-sensitive configuration belongs in manifests or generated values with a
clear source. Sensitive values belong in SOPS-encrypted manifests or bootstrap
Secrets according to ownership.

Applications consume Secrets; they should not generate undocumented credentials
at startup when reproducible recovery depends on them.

## Environment changes

An overlay may change:

- Storage class and capacity
- Resource requests and limits
- Replicas
- Ingress class and hostnames
- Certificate issuer
- Service type and firewall annotations
- DNS target and visibility

Avoid embedding provider-specific values in shared bases. The Civo overlay owns
Civo storage classes, firewall IDs, and private-address publication behavior.

## Delivery verification

Verify in dependency order:

1. Required CRD and operator are healthy.
2. Workload resource reports ready.
3. Service selectors produce EndpointSlices.
4. Load balancer and firewall match the intended visibility.
5. DNS resolves to the intended target.
6. Certificate is ready and trusted by the client.
7. Ingress routes the hostname to the correct Service.
8. Authentication and application-level health succeed.

For private applications, run these checks from a client whose route and DNS
configuration represent real use.

## GitOps boundary

Commit the desired application declaration and encrypted secrets. Runtime
controllers then create dependent objects. Continuous reconciliation applies
only where an Argo CD Application owns the resource; directly bootstrapped
resources still require the supported reconciliation workflow.

## Next step

Continue with the [Platform Component Catalog](10-platform-component-catalog.md).
