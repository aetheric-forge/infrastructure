# Prerequisites

This guide describes the operator workstation and external systems required to
configure and bootstrap Aetheric Forge Infrastructure. The v2.0 reference path
is a Civo development deployment operated from Linux.

Read [Deployment Models](02-deployment-models.md) before installing tools. The
requirements differ between Civo, local k3s, AWS, and Docker Compose.

## Operator workstation

The bootstrap scripts are Bash programs and assume a Linux environment with
standard GNU utilities. Ubuntu and Debian are the best-exercised operator
platforms. Other Linux distributions may work when equivalent tools are
available.

Use a workstation account that can:

- Read the Git and SOPS private keys selected during configuration
- Write its own kubeconfig under `~/.kube`
- Use `sudo` for local WireGuard installation when WireGuard is enabled
- Reach the selected cloud APIs, Git repository, Kubernetes API, public DNS
  provider, and internal DNS host

## Common command-line tools

Install the following before running the repository workflow:

| Tool | Used for |
| --- | --- |
| Bash, Make, Git, OpenSSH, curl | Repository workflow and remote gateway setup |
| Python 3 | Pulumi programs, CIDR validation, and bootstrap helpers |
| Pulumi CLI | Infrastructure and cluster provisioning |
| kubectl | Cluster access, bootstrap, and verification |
| Helm | Rendering controller charts through Kustomize |
| Kustomize | Rendering deployment overlays |
| SOPS and age | Decrypting and creating encrypted manifests |
| KSOPS | Allowing Kustomize to render SOPS-encrypted resources |
| jq | Processing Pulumi and Kubernetes JSON output |
| DNS utilities (`dig`) | Verifying resolver and authoritative DNS access |
| WireGuard tools | Creating keys and configuring the local tunnel |
| OpenSSL | Generating the private step-ca root when one is not supplied |

Install current supported releases using each project's official installation
instructions. Verify that the commands are available to the same user that will
run the bootstrap:

```bash
bash --version
git --version
python3 --version
pulumi version
kubectl version --client
helm version
kustomize version
sops --version
age --version
ksops --help
jq --version
dig -v
ssh -V
wg --version
openssl version
```

The two Pulumi projects have separate Python dependency sets. Install both in
the Python environment used for deployment:

```bash
python3 -m pip install -r scripts/pulumi/foundation/requirements.txt
python3 -m pip install -r scripts/pulumi/cluster/requirements.txt
```

Using a virtual environment is recommended. The repository ignores `.venv/`
and `venv/`.

## Shared external requirements

Every Kubernetes deployment requires:

- A writable Pulumi backend and selected Pulumi account or local backend
- A Git repository reachable over SSH by Argo CD
- A private SSH key authorized to read that repository
- An age identity matching the recipients used by the SOPS-encrypted manifests
- A Cloudflare zone and scoped API token for the public domain
- An internal DNS authority that accepts authenticated RFC2136 updates
- Separate TSIG secrets for ExternalDNS and cert-manager
- A base domain whose public and internal zones are under operator control

The reference DNS design uses Pi-hole on port 53 for client resolution and BIND
on port 5335 for the internal authoritative zone and RFC2136 updates. The
internal DNS host must be reachable from the cluster through the configured
private network path.

## Civo requirements

The v2.0 reference deployment additionally requires:

- A Civo account with permission to create networks, firewalls, instances,
  Kubernetes clusters, node pools, and load balancers
- A Civo API token exported as `CIVO_TOKEN`
- Capacity and quota in the selected Civo region
- An SSH public key file for the WireGuard gateway
- A public source CIDR allowed to reach the gateway's SSH and WireGuard ports
- A non-overlapping Civo network, WireGuard tunnel, and home network

Export the Civo token in the current shell; do not write it to the repository:

```bash
export CIVO_TOKEN="..."
```

The Civo workflow creates its own Kubernetes cluster and merges the resulting
kubeconfig into the operator's `~/.kube/config`.

## Local k3s requirements

The local path requires an existing k3s cluster and working current kubeconfig.
The repository does not install the operating system, k3s, LAN routing, or the
local LoadBalancer implementation.

Before bootstrap, confirm:

```bash
kubectl get nodes
```

See [Local k3s](local/k3s.md) and [Local BIND9](local/bind9.md) for the existing
host preparation notes. These documents have not yet received their complete
v2.0 accuracy pass.

## AWS requirements

The AWS path requires:

- An AWS account with permissions for the VPC, EC2, EKS, IAM, Route 53, and
  related resources declared by the Pulumi projects
- AWS credentials available to the AWS SDK and CLI
- The AWS CLI
- An EC2 key pair corresponding to the configured WireGuard SSH key name
- Sufficient regional quota for the requested network, gateway, cluster, and
  worker resources

Verify the active AWS identity before previewing or applying infrastructure:

```bash
aws sts get-caller-identity
```

AWS is implemented but is not the fully exercised v2.0 reference path.

## Docker Compose requirements

The Docker development stack requires Docker Engine and Docker Compose. It does
not require Pulumi, Kubernetes, WireGuard, KSOPS, or the cloud-provider CLIs
unless those tools are also needed for another deployment model.

See the [Docker development guide](../docker/README.md).

## Network planning

Choose non-overlapping IPv4 networks for:

- The cloud VPC or Civo private network
- The WireGuard tunnel
- The operator's home or local network
- Any existing Kubernetes Pod and Service networks

The WireGuard tunnel must be IPv4 and contain at least two usable addresses.
The first usable address is assigned to the cloud gateway and the second to the
local peer.

Although the current setting is named `WIREGUARD__LOCAL_CIDRS`, the v2.0 setup
scripts support one local IPv4 CIDR. Do not provide a comma-separated list.

## Key and file preparation

Prepare these files before running `make configure`:

- The Argo CD repository SSH private key
- The SOPS age identity file
- The WireGuard gateway SSH public key when WireGuard is enabled
- Optionally, an existing step-ca root certificate and its private key

Use absolute paths when answering file prompts. A path beginning with `~` that
is stored in `.env` is not expanded when later passed to commands as a variable.

Private keys must have restrictive filesystem permissions and must remain
outside Git.

## Preflight checklist

Before configuration, verify that:

- The chosen deployment model and environment overlay exist.
- All required commands run successfully.
- Cloud and Pulumi authentication target the intended account.
- Git SSH access works with the repository key.
- The SOPS age identity can decrypt the repository's encrypted manifests.
- Public and internal DNS zones are under your control.
- RFC2136 TCP and UDP traffic can reach the internal DNS host on port 5335.
- Planned networks do not overlap.
- The current account can use `sudo` if local WireGuard setup is required.

Continue to the [Configuration Reference](03-configuration-reference.md), then
the [Quick Start](01-quickstart.md).
