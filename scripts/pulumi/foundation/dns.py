import pulumi
import pulumi_aws as aws
from config import Config, AWSConfig, prefix
from network import Network


class Dns:
    def __init__(self, internal_zone):
        self.internal_zone = internal_zone


def create_dns(cfg: Config, network: Network) -> Dns:
    aws_cfg = cfg.aws
    if aws_cfg is None:
        raise Exception("required AWS configuration is missing. Run make configure.")

    name = prefix(cfg)

    internal = aws.route53.Zone(
        f"{name}-internal",
        name=cfg.internal_domain,
        vpcs=[
            aws.route53.ZoneVpcArgs(
                vpc_id=network.vpc.id,
                vpc_region=aws_cfg.region,
            )
        ],
        opts=pulumi.ResourceOptions(depends_on=[network.vpc]),
    )

    return Dns(internal)
