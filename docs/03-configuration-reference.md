# Configuration Reference

The interactive configuration command writes the repository-root `.env` file:

```bash
make configure
```

The file contains bootstrap inputs and secrets. It is ignored by Git and must
not be committed, copied into documentation, or used as a general secret store.
Running the configurator again replaces the existing file after confirmation.

## Value conventions

- Boolean values are lowercase `true` or `false`.
- CIDRs use IPv4 CIDR notation unless stated otherwise.
- Comma-separated settings must not contain spaces unless a consumer explicitly
  supports them.
- Use absolute filesystem paths. A stored `~` is not expanded when a value is
  later passed to another command.
- Environment and system names become part of cloud resource and kubeconfig
  names; use provider-safe lowercase names.

## Core settings

| Variable | Default | Description |
| --- | --- | --- |
| `CLOUD` | `local` | Deployment provider: `civo`, `aws`, or `local` |
| `ENVIRONMENT` | `dev` | Environment and Pulumi stack name |
| `ORG_NAME` | `aetheric-forge` | Organization portion of generated resource names |
| `SYSTEM_NAME` | `platform` | System portion of generated resource names |
| `PULUMI_STACK` | Value of `ENVIRONMENT` | Pulumi stack selected by repository scripts |

The generated cluster and kubeconfig name is
`ORG_NAME-SYSTEM_NAME-ENVIRONMENT`.

## Domain and DNS settings

| Variable | Default | Sensitive | Description |
| --- | --- | --- | --- |
| `BASE_DOMAIN` | `aethericforge.ca` | No | Parent domain for the deployment |
| `EXTERNAL_DOMAIN` | Value of `BASE_DOMAIN` | No | Public DNS zone used by the rendered platform |
| `INTERNAL_DOMAIN` | `int.` plus `BASE_DOMAIN` | No | Private platform DNS zone |
| `INT_DNS_HOST` | `localhost` | No | Hostname or address of BIND's RFC2136 listener; do not include a port |
| `EXT_DNS_TSIG_KEY` | None | Yes | TSIG secret value used by internal ExternalDNS |
| `CERT_MGR_TSIG_KEY` | None | Yes | TSIG secret value used by cert-manager DNS-01 challenges |
| `CF_API_KEY` | None | Yes | Scoped Cloudflare API token for public ExternalDNS |

The reference environment appends port 5335 when connecting directly to
`INT_DNS_HOST`. Client resolution uses the Pi-hole listener on port 53, which
forwards the internal zone to BIND.

The v2.0 Civo `dev` path is validated with `aethericforge.ca` and
`int.aethericforge.ca`. Some service bootstrap values still contain reference
environment hostnames. A different base domain requires a manifest and
generated-secret review; changing `BASE_DOMAIN` alone is not yet a guarantee
that every hostname will change.

## GitOps and encryption settings

| Variable | Default | Sensitive | Description |
| --- | --- | --- | --- |
| `GIT_REPO_URL` | None | No | SSH URL Argo CD uses to read the desired-state repository |
| `SSH_REPO_KEY` | `~/.ssh/argocd-repo` | Path is not secret; file is | Absolute path to the repository SSH private key |
| `SOPS_AGE_KEY` | `~/.config/sops/age/keys.txt` | Path is not secret; file is | Absolute path to the SOPS age identity file |

The displayed path defaults contain `~`; replace them with absolute paths when
accepting or editing the generated configuration.

SOPS-encrypted `.enc.yaml` resources are intentionally tracked. The age
identity, repository private key, `.env`, generated Pulumi environment, and
decrypted content remain local.

## Civo settings

These values are prompted only when `CLOUD=civo`.

| Variable | Default | Description |
| --- | --- | --- |
| `CIVO_REGION` | `NYC1` | Civo region used for all managed resources |
| `CIVO_NODE_SIZE` | `g4s.kube.small` | Instance size for the Kubernetes node pool |
| `CIVO_NODE_COUNT` | `1` | Initial Kubernetes node count |
| `CIVO_NODE_POOL_LABEL` | `workers` | Label assigned to the managed node pool |
| `CIVO_NETWORK_CIDR` | `10.60.0.0/24` | Dedicated Civo private-network CIDR |

The Civo provider reads its API credential from `CIVO_TOKEN` in the process
environment. `CIVO_TOKEN` is not written by the configurator.

Optional expert overrides:

| Variable | Default | Description |
| --- | --- | --- |
| `CIVO_K8S_VERSION` | Provider default | Requested Civo Kubernetes version |
| `CIVO_WIREGUARD_SIZE` | `g3.xsmall` | Instance size for the WireGuard gateway |

Review provider availability before overriding a region, node size, gateway
size, or Kubernetes version.

## AWS settings

These values are prompted only when `CLOUD=aws`.

| Variable | Default | Description |
| --- | --- | --- |
| `AWS__REGION` | `ca-west-1` | AWS region for foundation and cluster resources |
| `AWS__VPC_CIDR` | `10.42.0.0/16` | VPC network created by the foundation project |
| `AWS__K8S_VERSION` | `1.34` | Requested EKS Kubernetes version |
| `AWS__NODE_ARCH` | `arm64` | Worker architecture; ARM aliases select Graviton nodes |
| `AWS__NODE_DESIRED_SIZE` | `2` | Desired worker count |
| `AWS__NODE_MIN_SIZE` | `2` | Minimum worker count |
| `AWS__NODE_MAX_SIZE` | `4` | Maximum worker count |
| `AWS__CLUSTER_PUBLIC_ACCESS` | `false` | Whether the EKS API also receives a public endpoint |
| `AWS__KUBE_API_PUBLIC_ACCESS_CIDRS` | Current public IP `/32` | Public API allowlist, written only when public access is enabled |

AWS credentials follow the normal AWS SDK credential chain and are not written
to `.env` by the configurator.

AWS remains an implemented legacy path rather than the fully exercised v2.0
reference. Preview and validate its planned resources before applying it to a
new account.

## WireGuard settings

| Variable | Default | Description |
| --- | --- | --- |
| `WIREGUARD__ENABLED` | `true` | Whether cloud gateway and local tunnel setup are enabled |
| `WIREGUARD__SSH_KEY_NAME` | None | AWS EC2 key-pair name; currently prompted for every enabled provider but not consumed by Civo |
| `WIREGUARD__SSH_PUBLIC_KEY_FILE` | `~/.ssh/id_ed25519.pub` | Absolute path to the SSH public key installed on the Civo gateway |
| `WIREGUARD__TUNNEL_CIDR` | AWS/local: `10.200.10.0/24`; Civo: `10.200.20.0/24` | IPv4 tunnel network |
| `WIREGUARD__ACCESS_CIDRS` | Current public IP `/32` | Comma-separated source CIDRs allowed to reach the cloud gateway |
| `WIREGUARD__LOCAL_CIDRS` | `192.168.1.0/24` | Local network routed through the tunnel |

The tunnel CIDR is normalized before use. It must contain at least two usable
addresses; the gateway receives the first and the local peer receives the
second.

Despite their plural names, current setup behavior differs:

- `WIREGUARD__ACCESS_CIDRS` supports a comma-separated list in Civo firewall
  provisioning.
- `WIREGUARD__LOCAL_CIDRS` supports exactly one IPv4 CIDR. A comma-separated
  list will break interface discovery and firewall generation.

All cloud, tunnel, local, Kubernetes Pod, and Kubernetes Service networks must
be non-overlapping.

## Private certificate authority settings

| Variable | Default | Sensitive | Description |
| --- | --- | --- | --- |
| `STEP_CA__CERT_FILE` | Empty | No | Absolute path to an existing PEM root certificate |
| `STEP_CA__KEY_FILE` | Empty | Yes | Absolute path to the matching private key; required when a certificate is supplied |

When both values are empty, bootstrap generates a development root and writes
the encrypted Kubernetes resources required by the selected environment. When
supplying an existing root, verify that the certificate and key match before
bootstrap.

## Runtime credentials

These values are supplied to the current process rather than stored by
`make configure`:

| Variable or credential | Required for | Handling |
| --- | --- | --- |
| `CIVO_TOKEN` | Civo | Export a scoped Civo API token |
| AWS SDK credentials | AWS | Use an AWS profile, environment credentials, or another supported SDK source |
| Pulumi backend login | Cloud paths | Log in with `pulumi login`; provide backend credentials through Pulumi's supported mechanism |
| `PULUMI_CONFIG_PASSPHRASE` | Passphrase-backed Pulumi stacks | Export only when required by the selected backend |
| `KUBECONFIG` or `~/.kube/config` | Local k3s and cluster operations | Ensure the intended context is active before applying to an existing cluster |

Do not add these credentials to `.env` merely because it is ignored; keep each
credential in its provider's normal secure storage or process environment.

## Generated configuration

Provisioning writes `.env.pulumi.generated` from Pulumi stack outputs. It can
contain values such as:

- Cloud network and subnet identifiers
- Cluster and load-balancer firewall identifiers
- WireGuard public and private addresses
- Civo network CIDR

The file is regenerated, ignored by Git, and must not be edited by hand. The
scripts also generate rendered Kubernetes manifests and Pulumi stack files that
are ignored by Git.

The repository intentionally tracks SOPS-encrypted `.enc.yaml` manifests. It
does not track plaintext environment files, generated Pulumi configuration,
rendered manifests, local WireGuard keys, kubeconfigs, or CA private keys.

## Configuration review

After running `make configure`, inspect `.env` locally without pasting its
secret values into logs or reviews. Confirm:

- The cloud and environment are correct.
- Domain names and the internal DNS host describe the intended environment.
- Every file path is absolute and readable.
- CIDRs are valid and non-overlapping.
- `WIREGUARD__LOCAL_CIDRS` contains one CIDR.
- Provider credentials are available outside the file.
- The selected Pulumi stack is safe to preview and update.

Continue to the [Quick Start](01-quickstart.md).
