import os
import ipaddress
import pulumi
import pulumi_aws as aws
import pulumi_gcp as gcp
from config import Config, prefix

GCP_PODS_RANGE_NAME = "pods"
GCP_SERVICES_RANGE_NAME = "services"


class Network:
    def __init__(
        self,
        vpc=None,
        public_subnets=None,
        private_subnets=None,
        gcp_network=None,
        gcp_subnetwork=None,
    ):
        self.vpc = vpc
        self.public_subnets = public_subnets or []
        self.private_subnets = private_subnets or []
        self.gcp_network = gcp_network
        self.gcp_subnetwork = gcp_subnetwork


def create_network(cfg: Config) -> Network:
    if cfg.cloud == "gcp":
        return create_gcp_network(cfg)
    return create_aws_network(cfg)


def create_aws_network(cfg: Config) -> Network:
    aws_cfg = cfg.aws
    if aws_cfg is None:
        raise Exception("Required AWS configuration is missing. Run make configure")

    name = prefix(cfg)
    vpc_cidr = ipaddress.ip_network(aws_cfg.vpc_cidr)

    vpc = aws.ec2.Vpc(
        f"{name}-vpc",
        cidr_block=str(vpc_cidr),
        enable_dns_support=True,
        enable_dns_hostnames=True,
        tags={"Name": f"{name}-vpc"},
    )

    igw = aws.ec2.InternetGateway(
        f"{name}-igw",
        vpc_id=vpc.id,
    )

    # AZ selection
    azs = aws.get_availability_zones().names[:2]

    public_subnets = []
    private_subnets = []

    subnets = list(vpc_cidr.subnets(new_prefix=24))

    for i, az in enumerate(azs):
        public_subnets.append(
            aws.ec2.Subnet(
                f"{name}-public-{i}",
                vpc_id=vpc.id,
                cidr_block=str(subnets[i]),
                availability_zone=az,
                map_public_ip_on_launch=True,
            )
        )

        private_subnets.append(
            aws.ec2.Subnet(
                f"{name}-private-{i}",
                vpc_id=vpc.id,
                cidr_block=str(subnets[i + len(azs)]),
                availability_zone=az,
                map_public_ip_on_launch=False,
            )
        )

   # Route table for public
    public_rt = aws.ec2.RouteTable(
        f"{name}-public-rt",
        vpc_id=vpc.id,
        routes=[
            aws.ec2.RouteTableRouteArgs(
                cidr_block="0.0.0.0/0",
                gateway_id=igw.id,
            )
        ],
    )

    for i, subnet in enumerate(public_subnets):
        aws.ec2.RouteTableAssociation(
            f"{name}-public-rta-{i}",
            subnet_id=subnet.id,
            route_table_id=public_rt.id,
        )

    # NAT (single for now, keep it simple)
    eip = aws.ec2.Eip(f"{name}-nat-eip")

    nat = aws.ec2.NatGateway(
        f"{name}-nat",
        allocation_id=eip.id,
        subnet_id=public_subnets[0].id,
    )

    private_rt = aws.ec2.RouteTable(
        f"{name}-private-rt",
        vpc_id=vpc.id,
        routes=[
            aws.ec2.RouteTableRouteArgs(
                cidr_block="0.0.0.0/0",
                nat_gateway_id=nat.id,
            )
        ],
    )

    for i, subnet in enumerate(private_subnets):
        aws.ec2.RouteTableAssociation(
            f"{name}-private-rta-{i}",
            subnet_id=subnet.id,
            route_table_id=private_rt.id,
        )

    return Network(
        vpc=vpc,
        public_subnets=public_subnets,
        private_subnets=private_subnets,
    )


def create_gcp_network(cfg: Config) -> Network:
    gcp_cfg = cfg.gcp
    if gcp_cfg is None:
        raise Exception("Required GCP configuration is missing. Run make configure")

    name = prefix(cfg)
    vpc_cidr = ipaddress.ip_network(gcp_cfg.vpc_cidr)
    subnets = list(vpc_cidr.subnets(new_prefix=min(24, vpc_cidr.prefixlen + 4)))
    node_cidr = subnets[0]
    pods_cidr = subnets[1] if len(subnets) > 1 else subnets[0]
    services_cidr = subnets[2] if len(subnets) > 2 else subnets[0]

    network = gcp.compute.Network(
        f"{name}-vpc",
        name=f"{name}-vpc",
        auto_create_subnetworks=False,
        project=gcp_cfg.project,
    )

    subnetwork = gcp.compute.Subnetwork(
        f"{name}-subnet",
        name=f"{name}-subnet",
        project=gcp_cfg.project,
        region=gcp_cfg.region,
        network=network.id,
        ip_cidr_range=str(node_cidr),
        private_ip_google_access=True,
        # Dual-stack: the WireGuard gateway needs a real external IPv6
        # address for operators who have no public IPv4 at all (common on
        # residential ISPs), not just IPv4 behind CGNAT.
        stack_type="IPV4_IPV6",
        ipv6_access_type="EXTERNAL",
        secondary_ip_ranges=[
            gcp.compute.SubnetworkSecondaryIpRangeArgs(
                range_name=GCP_PODS_RANGE_NAME,
                ip_cidr_range=str(pods_cidr),
            ),
            gcp.compute.SubnetworkSecondaryIpRangeArgs(
                range_name=GCP_SERVICES_RANGE_NAME,
                ip_cidr_range=str(services_cidr),
            ),
        ],
    )

    router = gcp.compute.Router(
        f"{name}-router",
        name=f"{name}-router",
        project=gcp_cfg.project,
        region=gcp_cfg.region,
        network=network.id,
    )

    gcp.compute.RouterNat(
        f"{name}-nat",
        name=f"{name}-nat",
        project=gcp_cfg.project,
        region=gcp_cfg.region,
        router=router.name,
        nat_ip_allocate_option="AUTO_ONLY",
        source_subnetwork_ip_ranges_to_nat="ALL_SUBNETWORKS_ALL_IP_RANGES",
    )

    # Allow the WireGuard gateway (and anything else on the VPC) to reach the
    # private GKE nodes/control plane — GCP VPC firewalls default-deny ingress.
    gcp.compute.Firewall(
        f"{name}-allow-internal",
        name=f"{name}-allow-internal",
        project=gcp_cfg.project,
        network=network.id,
        allows=[
            gcp.compute.FirewallAllowArgs(protocol="tcp"),
            gcp.compute.FirewallAllowArgs(protocol="udp"),
            gcp.compute.FirewallAllowArgs(protocol="icmp"),
        ],
        source_ranges=[gcp_cfg.vpc_cidr],
    )

    return Network(
        gcp_network=network,
        gcp_subnetwork=subnetwork,
    )
