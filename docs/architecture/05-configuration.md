# Configuration Management

Aetheric Forge configuration is divided by lifecycle rather than stored in one
universal file.

## Configuration sources

| Source | Purpose | Git status |
| --- | --- | --- |
| `.env` | Operator inputs and bootstrap credentials | Ignored |
| Process environment | Provider authentication such as `CIVO_TOKEN` | Not stored |
| Pulumi programs | Infrastructure declarations | Tracked |
| Pulumi stack files | Local/backend stack configuration | Ignored in this repository |
| `.env.pulumi.generated` | Selected Pulumi outputs for later stages | Generated and ignored |
| Kustomize bases | Reusable platform definitions | Tracked |
| Cluster overlays | Provider/environment composition and patches | Tracked |
| SOPS `.enc.yaml` files | Encrypted desired secret state | Tracked |
| Rendered phase manifests | Apply-time artifacts | Generated and ignored |

See the [Configuration Reference](../03-configuration-reference.md) for every
interactive setting, advanced override, and current input constraint.

## Configuration flow

```text
Operator input ──► .env
                     │
                     ├──► Pulumi programs ──► cloud resources
                     │                           │
                     │                           ▼
                     └────────────────► .env.pulumi.generated
                                                 │
Git bases + environment overlay + generated values
                         │
                         ▼
                  rendered phase manifest
                         │
                         ▼
                     Kubernetes
```

The deployment script replaces explicit placeholders only after rendering an
overlay and fails if required placeholders remain unresolved.

## Naming and environment identity

`ORG_NAME`, `SYSTEM_NAME`, and `ENVIRONMENT` form cloud resource and kubeconfig
names. `BASE_DOMAIN` derives the external and internal domain inputs. Provider
overlays select storage classes, ingress behavior, firewall annotations, and
network integration.

The Civo v2 reference is the `dev` overlay. Some service bootstrap values still
contain reference-environment hostnames, so changing `BASE_DOMAIN` alone does
not yet retarget every component.

## Provider configuration

### Civo

Civo inputs select region, node size/count, node-pool label, private-network
CIDR, optional Kubernetes version, and WireGuard gateway size. The API token is
supplied through the process environment.

### AWS

AWS nested inputs describe region, VPC, EKS version, node architecture and
scaling, and public API access. AWS credentials use the normal SDK chain. The
AWS path remains implemented but is not the fully exercised v2 reference.

### Local

Local mode uses an existing kubeconfig and the shared `dev` overlay. Host,
LoadBalancer, routing, and authoritative DNS configuration remain
operator-owned.

## Generated output

Pulumi exports values such as network IDs, firewall IDs, gateway addresses, and
kubeconfig. `generate-env.sh` excludes the kubeconfig and writes other outputs
to `.env.pulumi.generated` using uppercase names.

Generated output is a transport between stages, not an authoritative file to
edit. Correct the Pulumi declaration or input and regenerate it.

## Secrets in configuration

`.env` contains bootstrap secret values and paths, but it is not committed.
Bootstrap creates initial Kubernetes Secrets and uses SOPS for encrypted
desired-state Secrets. Provider tokens, private keys, and age identities remain
outside Git.

Configuration examples must use placeholders rather than real credentials.
Encrypted ciphertext may be committed only in the expected `.enc.yaml` form.

## Change rules

- Preview Pulumi changes before applying infrastructure configuration.
- Render and inspect overlays before applying Kubernetes configuration.
- Change operator-created child resources through the owning custom resource.
- Preserve existing encrypted service credentials during ordinary upgrades.
- Do not edit generated output to conceal a mismatch in its source.
- Validate domain and CIDR inputs across every dependent system.

## Current constraints

- `WIREGUARD__LOCAL_CIDRS` currently accepts one IPv4 CIDR despite its plural
  name.
- The WireGuard tunnel is IPv4 and requires at least two usable addresses.
- Civo private addresses must be rediscovered after load-balancer replacement.
- Not every reference hostname is parameterized yet.
- Local and AWS paths have not received the same end-to-end v2 validation as
  Civo.

## Next step

Continue with [PKI Architecture](06-pki.md).
