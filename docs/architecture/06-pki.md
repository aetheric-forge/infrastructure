# PKI Architecture

Aetheric Forge uses separate public and private trust domains. cert-manager
automates certificate lifecycle for both, while step-ca provides the private
ACME authority.

## Trust boundaries

| Use | Issuer | Trust source | Validation |
| --- | --- | --- | --- |
| Public ingress | Public ACME issuer | Public operating-system/browser roots | Public DNS-01 |
| Internal ingress and services | step-ca ACME issuer | Aetheric Forge private root | Internal DNS-01 through BIND |

An internal hostname must not depend on public certificate authority
validation. A public certificate must not imply that an internal service should
be exposed publicly.

## Components

### cert-manager

cert-manager watches Certificate and issuer resources, creates ACME Orders and
Challenges, and writes issued key pairs to Kubernetes Secrets. It owns renewal
timing and the generated TLS Secret lifecycle.

### step-ca

step-ca runs inside the cluster as the private certificate authority and ACME
server. It uses the SOPS-encrypted root and provisioner secrets prepared for the
environment.

### BIND

BIND is authoritative for the internal zone on port 5335. cert-manager uses its
dedicated TSIG key to create and remove `_acme-challenge` TXT records.

## Private issuance flow

```text
Certificate
    │
    ▼
cert-manager ──► step-ca ACME order
    │
    ├── RFC2136 TXT update ──► BIND :5335
    └── DNS-01 self-check ───► BIND :5335
                                  │
step-ca validates challenge ◄─────┘
    │
    ▼
cert-manager stores TLS Secret
```

The self-check deliberately bypasses Pi-hole. A caching resolver can retain a
negative answer created immediately before the challenge record, while the
authoritative BIND answer is already correct.

## Public issuance flow

Public ingress Certificates use the public ACME ClusterIssuer. ExternalDNS
publishes the public hostname through Cloudflare, and the public ACME service
validates the corresponding challenge.

Public issuance therefore depends on public DNS delegation and propagation,
not the internal Pi-hole/BIND path.

## Trust bootstrap

After step-ca starts, the bootstrap workflow:

1. Reads the root certificate from the running step-ca Pod.
2. Creates or updates the cert-manager trust Secret.
3. Patches the internal ACME ClusterIssuer with the CA bundle.
4. Leaves cert-manager to issue and renew workload certificates.

Clients still need the private root in their own trust stores. Installing it in
Kubernetes does not automatically establish trust in an operator workstation,
browser profile, mobile device, or application-specific certificate store.

## Secret ownership

- The private root key and step-ca provisioner passwords are encrypted desired
  state.
- The SOPS age identity capable of decrypting them remains outside Git.
- Issued TLS Secrets are runtime state owned by cert-manager.
- A Certificate resource, not its generated Secret, is the durable place to
  change names, issuer, or renewal behavior.

Loss of the root private key prevents faithful CA recovery. Compromise of that
key compromises the private trust domain. Back it up separately and test the
recovery procedure.

## Renewal dependencies

Private renewal requires all of the following at renewal time:

- step-ca is healthy and trusts its configured root/provisioner state.
- cert-manager trusts the step-ca ACME endpoint.
- cert-manager can reach BIND on TCP and UDP port 5335.
- BIND accepts the cert-manager TSIG key.
- Authoritative TXT queries return the new challenge value.
- WireGuard routing, forwarding, and source NAT return replies to the cluster.

A currently valid certificate can conceal a broken renewal path. Validate an
actual Order/Challenge cycle after networking or DNS changes.

## Diagnosis order

1. Certificate condition and events
2. Order and Challenge state
3. cert-manager controller logs
4. Direct authoritative TXT answer on BIND port 5335
5. BIND update log and TSIG identity
6. WireGuard route, forwarding, and return traffic
7. step-ca health and ACME logs

Do not delete a valid TLS Secret until the issuance dependency failure is
understood.

## Next step

Continue with [Networking Architecture](07-networking.md).
