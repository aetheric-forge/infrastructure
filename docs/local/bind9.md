# Local Development: DNS Configuration

This guide configures the local RFC2136 DNS authority used by Aetheric Forge.

The local deployment model uses BIND9 as the authoritative DNS server for internal platform records.

---

## Why DNS Matters

Many platform services rely on DNS for discovery and certificate issuance.

Examples include:

- Argo CD
- Internal ingress
- Certificate management
- ExternalDNS reconciliation

A functioning authoritative DNS service is required before bootstrap can complete successfully.

---

## DNS Architecture

Local development uses:

```text
Applications
      │
ExternalDNS
      │
RFC2136
      │
BIND9
      │
Local Zone
```

BIND9 acts as the authoritative DNS server.

ExternalDNS manages records automatically through RFC2136 dynamic updates.

---

## Install BIND9

Ubuntu and Debian:

```bash
sudo apt update
sudo apt install -y bind9 bind9-utils
```

Verify service status:

```bash
sudo systemctl status named
```

or

```bash
sudo systemctl status bind9
```

depending on distribution.

---

## Configure the Local Zone

The bootstrap process assumes a dedicated internal zone.

Example:

```text
int.example.local
```

Create the zone definition and zone file appropriate for your environment.

Detailed examples are provided in the configuration templates.

---

## Verify DNS Resolution

Validate authoritative responses:

```bash
dig @127.0.0.1 your-zone-name SOA
```

Confirm that the server responds correctly before continuing.

---

## Dynamic Updates

Aetheric Forge uses RFC2136 dynamic updates.

During bootstrap:

- TSIG credentials are generated
- ExternalDNS is configured
- DNS records are reconciled automatically

Manual DNS record management should not be required.

---

## Next Step

Continue to:

- Local Development Bootstrap
