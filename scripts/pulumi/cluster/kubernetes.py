import os
from pathlib import Path
import pulumi
import json
import pulumi_aws as aws
import pulumi_eks as eks
import pulumi_civo as civo

def must(name: str) -> str:
    v = os.getenv(name)
    if not v:
        raise Exception(f"Missing required env: {name}")
    return v


# --- Core inputs from .env ---
org_name = must("ORG_NAME")
system_name = must("SYSTEM_NAME")
environment = must("ENVIRONMENT")
cluster_name = f"{org_name}-{system_name}-{environment}"

cloud = os.getenv("CLOUD", "local")

if cloud not in {"local", "aws", "civo"}:
    raise ValueError(f"Unsupported cloud provider: {cloud}")

if cloud == "aws":
    vpc_id = must("VPC_ID")
    private_subnet_ids = must("PRIVATE_SUBNET_IDS").split(",")
    internal_zone_id = must("INTERNAL_ZONE_ID")
    node_min = int(os.getenv("NODE_MIN_SIZE", "1"))
    node_max = int(os.getenv("NODE_MAX_SIZE", "1"))
    node_desired = int(os.getenv("NODE_DESIRED_SIZE", "1"))

    node_arch = os.getenv("NODE_ARCH", "arm")

    if node_arch == "arm":
        instance_types = ["t4g.small"]
    else:
        instance_types = ["t3.small"]

k8s_version = os.getenv("K8S_VERSION", "1.34")

def create_civo_cluster():
    region = os.getenv("CIVO_REGION", "NYC1").upper()
    network_cidr = os.getenv("CIVO_NETWORK_CIDR", "10.60.0.0/24")
    node_count = int(os.getenv("CIVO_NODE_COUNT", "1"))
    node_size = os.getenv("CIVO_NODE_SIZE", "g4s.kube.small")
    node_pool_label = os.getenv("CIVO_NODE_POOL_LABEL", "workers")
    version = os.getenv("CIVO_K8S_VERSION")

    network = civo.Network(
        f"{cluster_name}-network",
        label=f"{cluster_name}-network",
        region=region,
        cidr_v4=network_cidr,
    )

    firewall = civo.Firewall(
        f"{cluster_name}-firewall",
        name=f"{cluster_name}-firewall",
        network_id=network.id,
        region=region,
        create_default_rules=True,
    )

    private_lb_firewall = civo.Firewall(
        f"{cluster_name}-private-lb-firewall",
        name=f"{cluster_name}-private-lb-firewall",
        network_id=network.id,
        region=region,
        create_default_rules=False,
        egress_rules=[
            {
                "label": "outbound-tcp",
                "protocol": "tcp",
                "port_range": "1-65535",
                "cidrs": ["0.0.0.0/0"],
                "action": "allow",
            },
            {
                "label": "outbound-udp",
                "protocol": "udp",
                "port_range": "1-65535",
                "cidrs": ["0.0.0.0/0"],
                "action": "allow",
            },
        ],
    )

    pulumi.export("private_lb_firewall_id", private_lb_firewall.id)

    create_civo_wireguard_gateway(network, region, network_cidr)

    args = {
        "name": cluster_name,
        "region": region,
        "network_id": network.id,
        "firewall_id": firewall.id,
        "cluster_type": "k3s",
        "pools": {
            "label": node_pool_label,
            "node_count": node_count,
            "size": node_size,
        },
        "write_kubeconfig": True,
    }
    if version:
        args["kubernetes_version"] = version

    return civo.KubernetesCluster(cluster_name, **args)


def create_civo_wireguard_gateway(network, region: str, network_cidr: str):
    access_cidrs = [
        cidr.strip()
        for cidr in os.getenv("WIREGUARD__ACCESS_CIDRS", "0.0.0.0/0").split(",")
        if cidr.strip()
    ]
    home_cidr = os.getenv("WIREGUARD__LOCAL_CIDRS", "192.168.1.0/24")
    tunnel_cidr = os.getenv("WIREGUARD__TUNNEL_CIDR", "10.200.10.0/24")
    public_key_path = Path(os.getenv("WIREGUARD_LOCAL_PUBLIC_KEY", "../../../.wireguard/local.pub"))
    ssh_key_path = Path(os.path.expanduser(os.getenv("WIREGUARD__SSH_PUBLIC_KEY_FILE", "~/.ssh/id_ed25519.pub")))

    if not public_key_path.is_absolute():
        public_key_path = Path(__file__).parent / public_key_path
    if not public_key_path.is_file():
        raise ValueError(f"Missing WireGuard public key: {public_key_path}")
    if not ssh_key_path.is_file():
        raise ValueError(f"Missing SSH public key: {ssh_key_path}")

    local_public_key = public_key_path.read_text().strip()
    ssh_public_key = ssh_key_path.read_text().strip()
    tunnel_prefix = tunnel_cidr.rsplit(".", 1)[0]

    gateway_firewall = civo.Firewall(
        f"{cluster_name}-wireguard-firewall",
        name=f"{cluster_name}-wireguard-firewall",
        network_id=network.id,
        region=region,
        create_default_rules=False,
        ingress_rules=[
            {
                "label": "wireguard",
                "protocol": "udp",
                "port_range": "51820",
                "cidrs": access_cidrs,
                "action": "allow",
            },
            {
                "label": "ssh",
                "protocol": "tcp",
                "port_range": "22",
                "cidrs": access_cidrs,
                "action": "allow",
            },
            {
                "label": "vpc-dns-tcp",
                "protocol": "tcp",
                "port_range": "5335",
                "cidrs": [network_cidr],
                "action": "allow",
            },
            {
                "label": "vpc-dns-udp",
                "protocol": "udp",
                "port_range": "5335",
                "cidrs": [network_cidr],
                "action": "allow",
            },
        ],
        egress_rules=[
            {
                "label": "outbound",
                "protocol": "tcp",
                "port_range": "1-65535",
                "cidrs": ["0.0.0.0/0"],
                "action": "allow",
            },
            {
                "label": "outbound-udp",
                "protocol": "udp",
                "port_range": "1-65535",
                "cidrs": ["0.0.0.0/0"],
                "action": "allow",
            },
        ],
    )

    ssh_key = civo.SshKey(
        f"{cluster_name}-wireguard-key",
        name=f"{cluster_name}-wireguard-key",
        public_key=ssh_public_key,
    )

    ubuntu = civo.get_disk_image_output(
        region=region,
        filters=[{"key": "name", "values": ["ubuntu-jammy"], "match_by": "exact"}],
    )
    disk_image_id = ubuntu.diskimages.apply(lambda images: images[0].id)

    cloud_init = f"""#!/bin/bash
set -euo pipefail
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard iptables
install -d -m 700 /etc/wireguard
wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
chmod 600 /etc/wireguard/private.key
cat >/etc/sysctl.d/99-wireguard.conf <<'EOF'
net.ipv4.ip_forward=1
EOF
sysctl --system
VPC_INTERFACE=$(ip route show default | awk 'NR == 1 {{print $5}}')
test -n "$VPC_INTERFACE"
cat >/etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/private.key)
Address = {tunnel_prefix}.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -A POSTROUTING -s {tunnel_cidr} -d {network_cidr} -o $VPC_INTERFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -D POSTROUTING -s {tunnel_cidr} -d {network_cidr} -o $VPC_INTERFACE -j MASQUERADE

[Peer]
PublicKey = {local_public_key}
AllowedIPs = {home_cidr},{tunnel_prefix}.2/32
EOF
systemctl enable --now wg-quick@wg0
"""

    gateway = civo.Instance(
        f"{cluster_name}-wireguard",
        hostname=f"{cluster_name}-wireguard",
        region=region,
        network_id=network.id,
        firewall_id=gateway_firewall.id,
        disk_image=disk_image_id,
        size=os.getenv("CIVO_WIREGUARD_SIZE", "g3.xsmall"),
        initial_user="civo",
        public_ip_required="true",
        sshkey_id=ssh_key.id,
        script=cloud_init,
        opts=pulumi.ResourceOptions(
            ignore_changes=["script", "publicIpRequired", "volumeType"]
        ),
    )

    pulumi.export("network_cidr", network_cidr)
    pulumi.export("wireguard_private_ip", gateway.private_ip)
    pulumi.export("wireguard_public_ip", gateway.public_ip)

def create_cluster():
    if cloud == "aws":
        # --- IAM role for nodes ---
        node_role = aws.iam.Role(
            f"{cluster_name}-node-role",
            assume_role_policy="""{
                "Version": "2012-10-17",
                "Statement": [{
                    "Action": "sts:AssumeRole",
                    "Principal": {"Service": "ec2.amazonaws.com"},
                    "Effect": "Allow"
                }]
            }""",
        )

        for policy in [
            "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
            "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
            "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
        ]:
            aws.iam.RolePolicyAttachment(
                f"{cluster_name}-{policy.split('/')[-1]}",
                role=node_role.name,
                policy_arn=policy,
            )

        wireguard_sg_id = must("WIREGUARD_SG_ID")
        cluster_sg = aws.ec2.SecurityGroup(
            f"{cluster_name}-eks-sg",
            vpc_id=vpc_id,
            description="{cluster_name} EKS control plane SG",
        )
        aws.ec2.SecurityGroupRule(
            f"{cluster_name}-wg-to-eks-rule",
            security_group_id=cluster_sg.id,
            type="ingress",
            protocol="tcp",
            from_port=443,
            to_port=443,
            source_security_group_id=wireguard_sg_id,
        )

        # --- EKS cluster ---
        cluster = eks.Cluster(
            cluster_name,
            name=cluster_name,
            version=k8s_version,
            vpc_id=vpc_id,
            cluster_security_group=cluster_sg,
            subnet_ids=private_subnet_ids,
            endpoint_private_access=True,
            endpoint_public_access=(os.getenv("CLUSTER_PUBLIC_ACCESS").lower() == "true"),
            skip_default_node_group=True,
            instance_roles=[node_role],
            tags={
                "k8s.io/cluster-autoscaler/enabled": "true",
                f"k8s.io/cluster-autoscaler/{cluster_name}": "owned",
            },
            create_oidc_provider=True
        )

        # --- Node group ---
        eks.ManagedNodeGroup(
            f"{cluster_name}-ng",
            cluster=cluster,
            node_role=node_role,
            subnet_ids=private_subnet_ids,
            scaling_config={
                "desired_size": node_desired,
                "min_size": node_min,
                "max_size": node_max,
            },
            instance_types=instance_types,
        )

        assume_role_policy = pulumi.Output.all(
            cluster.oidc_provider_arn,
            cluster.oidc_provider_url,
        ).apply(
            lambda args: json.dumps(
                {
                    "Version": "2012-10-17",
                    "Statement": [
                        {
                            "Effect": "Allow",
                            "Principal": {
                                "Federated": args[0]  # arn
                            },
                            "Action": "sts:AssumeRoleWithWebIdentity",
                            "Condition": {
                                "StringEquals": {
                                    f"{args[1].replace('https://', '')}:sub": [
                                        "system:serviceaccount:external-dns:external-dns-internal",
                                        "system:serviceaccount:cert-manager:cert-manager",
                                    ]
                                }
                            },
                        }
                    ],
                }
            )
        )

        route53_policy = aws.iam.Policy(
            f"{cluster_name}-route53-policy",
            policy="""{
                  "Version": "2012-10-17",
                  "Statement": [
                    {
                      "Effect": "Allow",
                      "Action": ["route53:ChangeResourceRecordSets"],
                      "Resource": ["arn:aws:route53:::hostedzone/%s"]
                    },
                    {
                      "Effect": "Allow",
                      "Action": [
                        "route53:ListHostedZones",
                        "route53:ListHostedZonesByName",
                        "route53:ListResourceRecordSets",
                        "route53:ChangeResourceRecordSets",
                      ],
                      "Resource": ["*"]
                    }
                  ]
                }"""
            % internal_zone_id,
        )

        route53_role = aws.iam.Role(
            f"{cluster_name}-route53-role",
            assume_role_policy=assume_role_policy,  # you already have this pattern for cluster
        )

        aws.iam.RolePolicyAttachment(
            f"{cluster_name}-route53-policy",
            role=route53_role.name,
            policy_arn=route53_policy.arn,
        )

        return cluster

    if cloud == "civo":
        return create_civo_cluster()

    return None
