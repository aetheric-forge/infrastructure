# GitOps Architecture

Git stores the intended platform declarations and their history. Argo CD is the
platform's reconciliation engine, but bootstrap remains responsible for
establishing the cluster, credentials, dependency order, and initial platform
state.

## Desired and actual state

```text
Git declarations ──► renderer/controller ──► Kubernetes objects
                                                │
                                                ▼
                                      runtime controller state
```

Desired state includes Kustomize bases and overlays, Helm values embedded in
overlays, Pulumi programs, Argo CD application definitions, and SOPS-encrypted
Secret manifests. Actual state includes the resources running in Kubernetes and
the external records or load balancers created by controllers.

## Git is authoritative for declarations

Git should contain:

- Reusable platform bases
- Deployment-model and environment overlays
- Controller and operator configuration
- Service and ingress declarations
- Certificate and DNS intent
- SOPS-encrypted secret manifests
- Pulumi source code

Git must not contain:

- `.env` or generated Pulumi output
- Provider tokens or plaintext credentials
- SOPS age identities
- Repository or WireGuard private keys
- Kubeconfig data
- Rendered phase manifests
- Runtime status or discovered addresses as an undocumented manual edit

## Bootstrap and Argo CD

The Civo v2 workflow renders and server-side applies four stages directly:

1. Core controllers
2. Platform configuration
3. Operators
4. Shared services

This ordering solves the initial dependency problem: CRDs and controllers must
exist before their dependent resources. Argo CD is deployed as a shared service
and receives repository access during bootstrap.

An environment becomes continuously GitOps-managed only for resources covered
by its registered Argo CD Applications. The presence of Argo CD alone does not
prove that every bootstrapped object is reconciled by Argo.

## Environment overlays

Reusable components live under `platform/`. Environment composition lives
under `clusters/`.

The v2 reference overlay is:

```text
clusters/single/civo/dev/
├── 10-platform-core
├── 20-platform-config
├── 30-platform-operators
└── 40-platform-services
```

Provider-specific behavior belongs in the provider overlay rather than a
shared base. Examples include Civo firewall annotations, storage classes,
private load-balancer targets, and WireGuard route agents.

## Controller chains

Some desired state crosses system boundaries:

```text
Ingress/Service declaration
        │
        ├──► ingress-nginx routing
        ├──► ExternalDNS record
        └──► cert-manager Certificate/Secret
```

A Git change is not complete until each relevant controller has reconciled it.
Health must be checked at every boundary rather than only in Argo CD.

## Safe change workflow

1. Identify the owner and environment overlay.
2. Change the smallest declarative source.
3. Render and validate locally.
4. Review generated differences.
5. Commit and push the change.
6. Reconcile through the environment's supported workflow.
7. Verify runtime and external effects.

Do not edit an operator-created Service if the operator custom resource owns its
template. Do not publish a Civo public status address as a private DNS target.
Do not force server-side-apply conflicts outside the scoped migration helper.

## Drift and recovery

Drift can exist in Kubernetes, Pulumi, DNS, cloud resources, or external home
network configuration. Argo CD can repair only the resources it owns. Pulumi
repairs infrastructure drift; bootstrap reruns or focused stages repair
bootstrap-owned state; external operators repair DNS delegation, routing, and
trust stores.

Before recovery, determine which reconciler is responsible. Multiple
reconcilers claiming the same field create conflict rather than resilience.

## Next step

Continue with [DNS Architecture](04-dns.md).
