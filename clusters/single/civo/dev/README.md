# Civo dev private service DNS

The Civo overlay exposes RabbitMQ, MongoDB, and PostgreSQL through LoadBalancer
Services using the existing private load-balancer firewall. `scripts/create.sh`
looks up each Service's Civo load-balancer ID, reads its `private_ip`, and checks
that the address is IPv4, private, and inside `NETWORK_CIDR` (normally
`10.60.0.0/24`). The public IP reported in Kubernetes Service status is not used
for these DNS targets.

| Internal hostname | Private target |
| --- | --- |
| `amqp-dev.int.aethericforge.ca` | `rabbitmq/rabbitmq` load balancer |
| `forge-mongo-dev.int.aethericforge.ca` | `forge-mongo/forge-mongo-lb` load balancer |
| `forge-db-dev.int.aethericforge.ca` | `forge-db/forge-db-dev-lb` load balancer |
| `s3-dev.int.aethericforge.ca` | Private ingress-nginx load balancer, via the S3 ingress |

Service deployment runs in two passes. The first provisions the load balancers
with an ExternalDNS controller annotation that excludes them from publication.
After all three private addresses are discovered, the second writes their target
annotations and enables publication. RabbitMQ and PostgreSQL annotations live in
the operator resource's Service template, so operator reconciliation retains them.
The final rendered `platform-services.yaml` contains the discovered targets.

If discovery fails, publication stays disabled; fix the error and rerun. With
ExternalDNS's `sync` policy, previously managed records can disappear during this
interval. Rerun after a load balancer is recreated to refresh its private target;
this bootstrap script is not a continuous IP discovery controller.

## Apply to an existing cluster

Use the intended dev kubeconfig context, the repository's `.env` and current
`.env.pulumi.generated`, and an exported `CIVO_TOKEN`. The generated outputs must
include `NETWORK_CIDR`, `PRIVATE_LB_FIREWALL_ID`, and `WIREGUARD_PRIVATE_IP`.
The normal bootstrap dependencies (kubectl, Kustomize, Helm, KSOPS/age, curl, jq,
and Python 3) and secret decryption access are required.

From the repository root:

```bash
bash scripts/create.sh --platform-services
```

This reapplies the complete platform-services stage and discovers the existing
ingress addresses. It does not rerun Pulumi, provision the cluster, or reinstall
platform controllers. The ordinary full bootstrap invokes the same two-pass flow.

If an existing deployment reports ownership conflicts for MongoDB's
`kubernetes.civo.com/firewall-id` or PostgreSQL's
`spec.managed.services.additional`, run this one-time migration:

```bash
bash scripts/create.sh --platform-services --adopt-service-fields
```

It force-applies only that firewall annotation and the desired PostgreSQL
additional-Service list (an atomic CRD field), using a temporary field manager.
The normal manifest apply still checks all other conflicts. After it succeeds,
the temporary manager relinquishes ownership so subsequent updates use normal
apply. Review the desired additional-Service list before migrating if you have
added other managed Services outside this repository. An interrupted migration
can be rerun with the same flag.

After operators reconcile and ExternalDNS syncs, check the Service target
annotations, resolve the four names through internal DNS, and test service access
from the private network. The targets should be in `NETWORK_CIDR`. Independently
verify that each Civo load balancer has the intended private firewall attached.

## Offline tests

With test dependencies PyYAML and jsonpatch installed:

```bash
python3 -m unittest discover -s scripts/tests -v
bash -n scripts/create.sh scripts/lib/civo-loadbalancers.sh
```

The tests apply the actual overlay's JSON patches and exercise private-IP
validation and both deployment passes with mocked external commands. They do
not contact Civo, Kubernetes, or DNS.
