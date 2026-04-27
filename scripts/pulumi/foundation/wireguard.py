import os
import pulumi
import pulumi_aws as aws
from config import Config, prefix
from network import Network


class Wireguard:
    def __init__(self, instance, public_ip, security_group):
        self.instance = instance
        self.public_ip = public_ip
        self.security_group = security_group


def create_wireguard(cfg: Config, network: Network) -> Wireguard | None:
    if not cfg.wg_enabled:
        return None

    name = prefix(cfg)

    # SSH key
    public_key = open(os.path.expanduser(cfg.wg_ssh_public_key_file)).read()

    aws.ec2.KeyPair(
        f"{name}-wg-key",
        key_name=cfg.wg_ssh_key_name,
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
                cidr_blocks=cfg.wg_access_cidrs,
            ),
            aws.ec2.SecurityGroupIngressArgs(
                protocol="tcp",
                from_port=22,
                to_port=22,
                cidr_blocks=cfg.wg_access_cidrs,
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

    # EIP for public access
    eip = aws.ec2.Eip(f"{name}-wg-eip")

    # Private ENI (primary)
    private_eni = aws.ec2.NetworkInterface(
        f"{name}-wg-private-eni",
        subnet_id=network.private_subnets[0].id,
        security_groups=[sg.id],
    )

    # Public ENI
    public_eni = aws.ec2.NetworkInterface(
        f"{name}-wg-public-eni",
        subnet_id=network.public_subnets[0].id,
        security_groups=[sg.id],
    )

    eip_assoc = aws.ec2.EipAssociation(
        f"{name}-wg-eip-assoc",
        network_interface_id=public_eni.id,
        allocation_id=eip.id,
        opts=pulumi.ResourceOptions(parent=public_eni),
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
        key_name=cfg.wg_ssh_key_name,
        primary_network_interface=aws.ec2.InstancePrimaryNetworkInterfaceArgs(
            network_interface_id=private_eni.id,
        ),
        user_data=user_data,
    )

    aws.ec2.NetworkInterfaceAttachment(
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
    )
