# DNS Architecture

Aetheric Forge separates public naming from private naming and separates
ordinary client resolution from authoritative dynamic updates.

## Zone boundaries

The v2 reference uses two distinct zones:

| Zone | Visibility | Authority | Reconciler |
| --- | --- | --- | --- |
| External domain | Public | Cloudflare | Public ExternalDNS |
| Internal domain | Private | BIND | RFC2136 ExternalDNS |

The default reference domains are `aethericforge.ca` and
`int.aethericforge.ca`. They are separate namespaces, not split-horizon views of
one zone.

## Resolver and authority roles

The home DNS host exposes two logical services:

- Pi-hole on port 53 answers ordinary client DNS queries.
- BIND on port 5335 is authoritative for the internal zone and accepts
  authenticated RFC2136 updates.

Pi-hole forwards the internal zone to BIND:

```text
Private client ──► Pi-hole :53 ──► BIND :5335
                                      │
                                      └── authoritative internal answer
```

BIND may run on the same host, but the ports and responsibilities remain
distinct.

## Publication paths

Two ExternalDNS instances run in the cluster:

```text
Public Ingress/Service ──► Cloudflare ExternalDNS ──► public zone

Private Ingress/Service ──► RFC2136 ExternalDNS ──► BIND :5335
```

Each instance has its own domain filter, registry owner, provider credentials,
and visibility boundary. Public ExternalDNS excludes the internal domain.

Internal updates use a dedicated TSIG key. cert-manager uses a separate TSIG
key for DNS-01 challenge records. BIND policy must authorize each key only for
its intended names and operations.

## Civo private targets

Civo LoadBalancer Services can report a publicly routable address in
Kubernetes status even when the intended consumer is private. The bootstrap
therefore does not use Service status as the internal DNS target.

For RabbitMQ, MongoDB, and PostgreSQL, deployment proceeds in two passes:

1. Create the Services with internal DNS publication disabled.
2. Query Civo for each load balancer's private address.
3. Validate that every address is private and belongs to the configured Civo
   network.
4. Reapply the owning resources with explicit ExternalDNS target annotations.

The MinIO S3 hostname targets the private ingress load balancer. Internal web
applications also use private ingress; public Keycloak uses public ingress.

Private-address discovery is a deployment operation, not a continuous
controller. Replace a load balancer only with a plan to rerun discovery and
verify its record.

## ACME DNS-01 path

Private certificate issuance depends on fresh authoritative TXT answers:

```text
cert-manager ── RFC2136 update ──► BIND :5335
cert-manager ── DNS-01 self-check ► BIND :5335
step-ca     ── challenge lookup ──► configured resolver path
```

cert-manager's recursive self-check is directed to BIND rather than Pi-hole.
This avoids stale negative cache entries after a challenge TXT record is
created. Ordinary clients continue to use Pi-hole on port 53.

## Network dependency

Cluster Pods reach the home DNS network through the Civo WireGuard gateway. The
path requires:

- Routes from cluster nodes and Pods toward the gateway
- IPv4 forwarding on both gateway endpoints
- Forwarding firewall rules
- Source NAT where the return network lacks a route to the original source
- TCP and UDP access to ports 53 and 5335 as appropriate

An RFC2136 log entry whose source is the gateway address is expected when source
NAT is used.

## Record ownership and deletion

ExternalDNS uses TXT ownership records and `sync` policy. Removing or disabling
the owning declaration can remove a previously managed record. During the first
pass of private-service deployment, publication is intentionally suppressed;
complete the second pass promptly after correcting a discovery failure.

Manual records can conflict with controller ownership. Emergency manual repair
must be followed by a correction to the owning manifest or controller inputs.

## Diagnosing DNS

Check the chain in order:

1. Route to the home DNS host.
2. Pi-hole answer on port 53.
3. Authoritative BIND answer on port 5335.
4. TSIG-authenticated update acceptance in BIND logs.
5. ExternalDNS or cert-manager events.
6. Final client answer and TTL/cache behavior.

Useful comparisons:

```bash
dig @"$INT_DNS_HOST" "$INTERNAL_DOMAIN" SOA
dig @"$INT_DNS_HOST" -p 5335 "$INTERNAL_DOMAIN" SOA
dig @"$INT_DNS_HOST" -p 5335 \
    "_acme-challenge.example.$INTERNAL_DOMAIN" TXT
```

Do not treat a successful RFC2136 update as proof that the client resolver,
route, or certificate controller sees the same answer.

## Next step

Continue with [Configuration Management](05-configuration.md).
