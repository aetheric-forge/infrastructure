import os
import ipaddress
import pulumi_aws as aws
from config import Config, prefix


class Network:
    def __init__(
        self,
        vpc,
        public_subnets,
        private_subnets,
    ):
        self.vpc = vpc
        self.public_subnets = public_subnets
        self.private_subnets = private_subnets


def create_network(cfg: Config) -> Network:
    name = prefix(cfg)
    vpc_cidr = ipaddress.ip_network(os.environ["AWS_VPC_CIDR"])

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
