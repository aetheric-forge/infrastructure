import os
import pulumi
import pulumi_aws as aws
import pulumi_gcp as gcp
from config import Config, prefix
from network import Network


class Wireguard:
    def __init__(self, instance, public_ip, security_group, public_eni=None, eni_attach=None, public_ipv6=None):
        self.instance = instance
        self.public_ip = public_ip
        self.public_ipv6 = public_ipv6
        self.security_group = security_group
        self.public_eni_urn = public_eni.urn if public_eni is not None else None
        self.eni_attach_urn = eni_attach.urn if eni_attach is not None else None


def create_wireguard(cfg: Config, network: Network) -> Wireguard | None:
    wg_cfg = cfg.wireguard
    if not wg_cfg or not wg_cfg.enabled:
        return None

    if not wg_cfg.ssh_public_key_file:
        return None

    if cfg.cloud == "gcp":
        return create_gcp_wireguard(cfg, network)
    return create_aws_wireguard(cfg, network)


def create_aws_wireguard(cfg: Config, network: Network) -> Wireguard | None:
    wg_cfg = cfg.wireguard
    name = prefix(cfg)

    # SSH key
    public_key = open(os.path.expanduser(wg_cfg.ssh_public_key_file)).read()

    aws.ec2.KeyPair(
        f"{name}-wg-key",
        key_name=wg_cfg.ssh_key_name,
        public_key=public_key,
    )

    # Security group
    sg = aws.ec2.SecurityGroup(
        f"{name}-wg-sg",
        vpc_id=network.vpc.id,
        description="WireGuard access",
        ingress=[
            aws.ec2.SecurityGroupIngressArgs(
                protocol="udp",
                from_port=51820,
                to_port=51820,
                cidr_blocks=wg_cfg.access_cidrs,
            ),
            aws.ec2.SecurityGroupIngressArgs(
                protocol="tcp",
                from_port=22,
                to_port=22,
                cidr_blocks=wg_cfg.access_cidrs,
            ),
        ],
        egress=[
            aws.ec2.SecurityGroupEgressArgs(
                protocol="-1",
                from_port=0,
                to_port=0,
                cidr_blocks=["0.0.0.0/0"],
            )
        ],
    )

    # 2) Make ENI (and anything that touches it) wait for that destroy step
    public_eni = aws.ec2.NetworkInterface(
        f"{name}-wg-public-eni",
        subnet_id=network.public_subnets[0].id,
        security_groups=[sg.id],
    )

    eip = aws.ec2.Eip(f"{name}-wg-eip")

    eip_assoc = aws.ec2.EipAssociation(
        f"{name}-wg-public-eip-assoc",
        allocation_id=eip.id,
        network_interface_id=public_eni.id,
    )

    # Private ENI (primary)
    private_eni = aws.ec2.NetworkInterface(
        f"{name}-wg-private-eni",
        subnet_id=network.private_subnets[0].id,
        security_groups=[sg.id],
    )

    user_data = """#!/bin/bash
set -e

# Enable IP forwarding
cat <<EOF >/etc/sysctl.d/99-wireguard.conf
net.ipv4.ip_forward=1
EOF
sysctl --system

# NAT for VPC access (private interface)
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# Persist iptables
yum install -y iptables-services || true
service iptables save || true
"""

    # Instance
    instance = aws.ec2.Instance(
        f"{name}-wg",
        instance_type="t4g.small",
        ami=aws.ec2.get_ami(
            most_recent=True,
            owners=["amazon"],
            filters=[
                {
                    "name": "name",
                    "values": ["al2023-ami-*-arm64"],
                }
            ],
        ).id,
        key_name=wg_cfg.ssh_key_name,
        primary_network_interface=aws.ec2.InstancePrimaryNetworkInterfaceArgs(
            network_interface_id=private_eni.id,
        ),
        user_data=user_data,
    )

    eni_attach = aws.ec2.NetworkInterfaceAttachment(
        f"{name}-wg-public-eni-attach",
        instance_id=instance.id,
        network_interface_id=public_eni.id,
        opts=pulumi.ResourceOptions(depends_on=[eip_assoc]),
        device_index=1,
    )

    return Wireguard(
        instance=instance,
        public_ip=eip.public_ip,
        security_group=sg,
        eni_attach=eni_attach,
        public_eni=public_eni,
    )


def create_gcp_wireguard(cfg: Config, network: Network) -> Wireguard | None:
    wg_cfg = cfg.wireguard
    gcp_cfg = cfg.gcp
    if gcp_cfg is None:
        raise Exception("required GCP configuration is missing. Run make configure.")

    name = prefix(cfg)

    firewall = gcp.compute.Firewall(
        f"{name}-wg-fw",
        name=f"{name}-wg-fw",
        project=gcp_cfg.project,
        network=network.gcp_network.id,
        allows=[
            gcp.compute.FirewallAllowArgs(protocol="udp", ports=["51820"]),
            gcp.compute.FirewallAllowArgs(protocol="tcp", ports=["22"]),
        ],
        source_ranges=wg_cfg.access_cidrs,
        target_tags=[f"{name}-wireguard"],
    )

    address = gcp.compute.Address(
        f"{name}-wg-ip",
        name=f"{name}-wg-ip",
        project=gcp_cfg.project,
        region=gcp_cfg.region,
    )

    # Generates its own WireGuard keypair on first boot, same approach as the
    # Civo gateway (no static private key baked into Pulumi state).
    startup_script = """#!/bin/bash
set -euo pipefail
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard iptables
install -d -m 700 /etc/wireguard
if [ ! -f /etc/wireguard/private.key ]; then
  wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
  chmod 600 /etc/wireguard/private.key
fi
cat >/etc/sysctl.d/99-wireguard.conf <<'EOF'
net.ipv4.ip_forward=1
EOF
sysctl --system
VPC_INTERFACE=$(ip route show default | awk 'NR == 1 {print $5}')
test -n "$VPC_INTERFACE"
iptables -t nat -A POSTROUTING -o "$VPC_INTERFACE" -j MASQUERADE
"""

    instance = gcp.compute.Instance(
        f"{name}-wg",
        name=f"{name}-wg",
        project=gcp_cfg.project,
        zone=gcp_cfg.zone,
        machine_type="e2-small",
        tags=[f"{name}-wireguard"],
        boot_disk=gcp.compute.InstanceBootDiskArgs(
            initialize_params=gcp.compute.InstanceBootDiskInitializeParamsArgs(
                image="debian-cloud/debian-12",
            ),
        ),
        network_interfaces=[
            gcp.compute.InstanceNetworkInterfaceArgs(
                network=network.gcp_network.id,
                subnetwork=network.gcp_subnetwork.id,
                stack_type="IPV4_IPV6",
                access_configs=[
                    gcp.compute.InstanceNetworkInterfaceAccessConfigArgs(
                        nat_ip=address.address,
                    )
                ],
                ipv6_access_configs=[
                    gcp.compute.InstanceNetworkInterfaceIpv6AccessConfigArgs(
                        network_tier="PREMIUM",
                    )
                ],
            )
        ],
        can_ip_forward=True,
        metadata={
            "ssh-keys": pulumi.Output.concat(
                "wireguard:",
                open(os.path.expanduser(wg_cfg.ssh_public_key_file)).read().strip(),
            ),
        },
        metadata_startup_script=startup_script,
        opts=pulumi.ResourceOptions(depends_on=[firewall]),
    )

    # Without this, nothing else in the VPC (GKE nodes/pods included) has any
    # path to the home LAN at all — the firewall rule alone doesn't give
    # traffic anywhere to go. This is what makes 192.168.1.1:5335 (BIND9)
    # actually reachable from the cluster, not just from the gateway itself.
    for i, local_cidr in enumerate(wg_cfg.local_cidrs or []):
        gcp.compute.Route(
            f"{name}-wg-home-route-{i}",
            name=f"{name}-wg-home-route-{i}",
            project=gcp_cfg.project,
            network=network.gcp_network.id,
            dest_range=local_cidr,
            next_hop_instance=instance.self_link,
            priority=1000,
        )

    public_ipv6 = instance.network_interfaces[0].ipv6_access_configs[0].external_ipv6

    return Wireguard(
        instance=instance,
        public_ip=address.address,
        public_ipv6=public_ipv6,
        security_group=firewall,
    )
