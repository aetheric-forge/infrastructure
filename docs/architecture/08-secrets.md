# Secrets Management

Aetheric Forge combines local bootstrap credentials, SOPS-encrypted desired
state, Kubernetes Secrets, and runtime-generated credentials. Encryption does
not remove the need for clear ownership and recovery keys.

## Secret categories

| Category | Examples | Storage |
| --- | --- | --- |
| Provider credentials | Civo token, Cloudflare token, AWS credentials | Provider store or process environment |
| Bootstrap keys | Repository SSH key, SOPS age identity, WireGuard private key | Operator-controlled filesystem |
| Encrypted desired state | Service passwords, CA material, OIDC client secrets | Tracked SOPS `.enc.yaml` manifests |
| Bootstrap Kubernetes Secrets | Argo repository access, SOPS identity, DNS tokens | Created directly by bootstrap |
| Runtime secrets | Issued TLS key pairs and controller-generated data | Kubernetes/controller state |

## SOPS and age

SOPS encrypts values while leaving enough Kubernetes structure for review. age
identities determine who can decrypt those values.

```text
Plaintext Secret ──► SOPS encryption ──► tracked .enc.yaml
                                                │
age identity + KSOPS/Kustomize ─────────────────┘
                         │
                         ▼
                 Kubernetes Secret
```

Only the encrypted manifest belongs in Git. The age identity never does.

## Repository policy

The repository intentionally tracks SOPS-encrypted `.enc.yaml` files. It ignores
and must not receive:

- `.env` and `.env.pulumi.generated`
- Pulumi stack configuration generated for an operator
- Kubeconfig files
- `.wireguard/` private keys
- Plaintext CA certificates/keys generated for bootstrap
- Rendered phase manifests
- Backup archives and logs containing credentials

Encryption must be verified, not inferred from a filename. Before committing a
new `.enc.yaml`, confirm that sensitive values are represented by SOPS `ENC[...]`
blocks and that the intended recipients can decrypt it.

## Bootstrap behavior

Bootstrap creates initial Secrets needed before encrypted manifests can be
rendered, including Argo CD repository access, the SOPS identity, and DNS
provider credentials.

For service secrets, bootstrap preserves an existing encrypted file. It creates
a new encrypted manifest only when the expected file and corresponding cluster
Secret are absent. This avoids silently rotating stateful-service credentials
during an ordinary rerun.

## Private CA material

The step-ca root key has a larger blast radius than an individual service
password. Its loss prevents faithful recovery; its compromise breaks the
private trust domain. Keep independent encrypted backups and test restore
procedures.

Distributing the root certificate to workloads and clients is not equivalent to
distributing the root private key. Only the certificate belongs in trust
bundles.

## Rotation

Rotate a secret through its owner:

| Secret | Rotation owner |
| --- | --- |
| Civo/Cloudflare token | Provider account plus local bootstrap input |
| RFC2136 TSIG key | BIND policy plus Kubernetes bootstrap Secret |
| Repository deploy key | Git provider plus Argo CD repository Secret |
| SOPS recipient | SOPS metadata plus securely distributed age identities |
| Service credential | Encrypted manifest and consuming service |
| Issued TLS key | cert-manager Certificate lifecycle |
| step-ca root | Dedicated CA migration, not ordinary credential rotation |

Plan dual-key or staged overlap where a provider supports it. Verify consumers
before revoking the old credential.

## Review and recovery

Secret recovery requires both ciphertext and decryption authority. Preserve:

- Git history containing the intended encrypted manifests
- At least one tested age identity for every recipient set
- Pulumi backend access
- Provider account recovery
- Repository deploy-key recovery
- CA root and service-data backups

Do not print decrypted content during routine validation. Test decryption by
discarding output or inspecting only non-sensitive metadata.

## Next step

Continue with [Application Delivery](09-application-delivery.md).
