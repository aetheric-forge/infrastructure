import pulumi_aws as aws
from config import Config, prefix
from network import Network


class Dns:
    def __init__(self, internal_zone, external_zone):
        self.internal_zone = internal_zone
        self.external_zone = external_zone


def create_dns(cfg: Config, network: Network) -> Dns:
    name = prefix(cfg)

    internal = aws.route53.Zone(
        f"{name}-internal",
        name=cfg.internal_domain,
        vpcs=[
            aws.route53.ZoneVpcArgs(
                vpc_id=network.vpc.id, vpc_region=network.vpc.region
            )
        ],
    )

    external = aws.route53.Zone(
        f"{name}-external",
        name=cfg.external_domain,
    )

    return Dns(internal, external)
