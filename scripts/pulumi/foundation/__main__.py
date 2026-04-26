import pulumi
from config import load_config
from network import create_network
from dns import create_dns
from wireguard import create_wireguard

cfg = load_config()

network = create_network(cfg)
dns = create_dns(cfg, network)
wg = create_wireguard(cfg, network)

if wg:
    pulumi.export("wireguard_sg_id", wg.security_group.id)
    pulumi.export("wireguard_public_ip", wg.public_ip)
    pulumi.export("internal_zone_id", dns.internal_zone.id)
    pulumi.export("external_zone_id", dns.external_zone.id)
