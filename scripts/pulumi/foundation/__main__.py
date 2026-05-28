import pulumi
from config import load_config
from dns import create_dns
from network import create_network
from wireguard import create_wireguard

cfg = load_config()

if cfg.cloud == "aws":
    network = create_network(cfg)
    pulumi.export("vpc_id", network.vpc.id)
    dns = create_dns(cfg, network)
    pulumi.export("internal_zone_id", dns.internal_zone.id)
    wg_cfg = cfg.wireguard
    if wg_cfg and wg_cfg.enabled:
        wg = create_wireguard(cfg, network)
        if wg:
            pulumi.export("wireguard_sg_id", wg.security_group.id)
            pulumi.export("wireguard_public_ip", wg.public_ip)

    pulumi.export(
        "private_subnet_ids",
        pulumi.Output.all(*[s.id for s in network.private_subnets]).apply(
            lambda ids: ",".join(ids)
        ),
    )

    pulumi.export(
        "public_subnet_ids",
        pulumi.Output.all(*[s.id for s in network.public_subnets]).apply(
            lambda ids: ",".join(ids)
        ),
    )
