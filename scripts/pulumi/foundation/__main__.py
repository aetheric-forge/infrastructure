import pulumi
from config import load_config
from network import create_network
from wireguard import create_wireguard

cfg = load_config()

network = create_network(cfg)
wg = create_wireguard(cfg, network)

pulumi.export("vpc_id", network.vpc.id)
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

if wg:
    pulumi.export("wireguard_sg_id", wg.security_group.id)
    pulumi.export("wireguard_public_ip", wg.public_ip)
