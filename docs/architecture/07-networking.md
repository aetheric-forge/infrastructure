# Networking Architecture

The v2.0 reference network connects public users, private clients, a Civo
Kubernetes cluster, and an external home DNS network without treating every
service as public.

## Network domains

| Domain | Purpose |
| --- | --- |
| Public internet | Public ingress and cloud-provider APIs |
| Civo private network | Cluster nodes, gateway, and private load balancers |
| WireGuard tunnel | Routed connection between Civo and the home router |
| Home LAN | Private clients and DNS authority |
| Kubernetes Pod/Service networks | Cluster-internal workload communication |

All CIDRs must be non-overlapping.

## Ingress classes

The Civo overlay installs two ingress-nginx controllers:

| Class | Load balancer | Intended traffic |
| --- | --- | --- |
| `nginx-public` | Public Civo load balancer | Explicitly public applications such as Keycloak |
| `nginx-private` | Civo load balancer with private firewall | Internal web consoles and APIs |

An Ingress must choose its class explicitly. DNS visibility and certificate
issuer must agree with that choice.

## Non-HTTP services

RabbitMQ, MongoDB, and PostgreSQL use dedicated LoadBalancer Services when
private clients need protocol-level access. Their internal records target Civo
private addresses discovered through the provider API.

Redis remains a ClusterIP in the Civo overlay. MinIO's console and S3 API use
private ingress hostnames rather than separate public service addresses.

## WireGuard topology

```text
Home LAN/client
      │
      ▼
Home router: wg-civo (second usable tunnel address)
      │
      │ encrypted tunnel
      ▼
Civo gateway: wg0 (first usable tunnel address)
      │
      ▼
Civo private network and cluster
```

The Civo gateway detects its default VPC interface at runtime. The home setup
detects the LAN interface used to reach the configured local CIDR. Tunnel peer
addresses are calculated from the configured IPv4 network rather than assuming
a `/24` or a particular dotted prefix.

## Forwarding and source NAT

Routing requires more than a current WireGuard handshake:

- IPv4 forwarding must be enabled on both routing hosts.
- Forward rules must permit the intended direction and connection state.
- The WireGuard peer `AllowedIPs` must include the routed networks.
- Source NAT is required where the destination network lacks a return route to
  the original source.
- Persistent `PostUp` and `PostDown` rules must match live firewall behavior.

The reference gateway masquerades traffic leaving toward the home CIDR so the
home network can return cluster-originated DNS and RFC2136 traffic without a
route for every Pod source.

The home router masquerades LAN and other configured sources toward the Civo
network where required. Broad, duplicate, or interface-mismatched rules can
hide routing errors and should not accumulate outside the managed config.

## Cluster node routes

The Civo overlay deploys a privileged route agent so cluster nodes route the
configured home CIDR through the WireGuard gateway's private address. This is
required for Pod-to-home traffic; a route on the operator workstation alone does
not affect cluster nodes.

## Load balancers

Civo owns cloud load-balancer allocation. Kubernetes Service status can expose
the provider's public address even when the platform intends private access.
Internal DNS therefore uses provider-discovered private addresses.

The shared local/AWS `dev` path retains MetalLB-oriented resources. MetalLB is
not part of the Civo reference data path and must not be described as the
universal platform load balancer.

## Failure boundaries

Diagnose a private connection in order:

1. Client route to the destination CIDR
2. Packet arrival on the home LAN interface
3. Forwarding/NAT from LAN to `wg-civo`
4. Current WireGuard handshake and packet counters
5. Forwarding/NAT on the Civo gateway
6. Civo private route, firewall, and load balancer
7. Kubernetes Service endpoints and healthy Pods

A successful ICMP test does not prove that TCP 443, DNS, or an application port
is allowed. Capture the specific protocol and endpoint being tested.

## Persistence

Live routes and firewall rules disappear after interface restart or reboot
unless represented in NetworkManager, WireGuard `PostUp`/`PostDown`, nftables
configuration, or another host-owned persistent mechanism. Document which
system owns each rule; do not maintain the same rule independently in several
places.

## Next step

Continue with [Secrets Management](08-secrets.md).
