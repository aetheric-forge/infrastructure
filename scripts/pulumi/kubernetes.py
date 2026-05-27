import os
import pulumi
import json
import pulumi_aws as aws
import pulumi_eks as eks
import pulumi_kubernetes as k8s


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

vpc_id = must("VPC_ID")
private_subnet_ids = must("PRIVATE_SUBNET_IDS").split(",")
internal_zone_id = must("INTERNAL_ZONE_ID")

k8s_version = os.getenv("K8S_VERSION", "1.34")

node_min = int(os.getenv("NODE_MIN_SIZE", "1"))
node_max = int(os.getenv("NODE_MAX_SIZE", "1"))
node_desired = int(os.getenv("NODE_DESIRED_SIZE", "1"))

node_arch = os.getenv("NODE_ARCH", "arm")

if node_arch == "arm":
    instance_types = ["t4g.small"]
else:
    instance_types = ["t3.small"]


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
            endpoint_public_access=(os.getenv("CLUSTER_PUBLIC_ACCESS") == True),
            skip_default_node_group=True,
            instance_roles=[node_role],
            tags={
                "k8s.io/cluster-autoscaler/enabled": "true",
                f"k8s.io/cluster-autoscaler/{cluster_name}": "owned",
            },
            create_oidc_provider=True,
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

    kubeconfig = cluster.kubeconfig if cloud == "aws" else "~/.kube/config"

    k8s_provider = k8s.Provider(
        f"{cluster_name}-k8s-provider",
        kubeconfig=kubeconfig,
    )

    external_dns_ns = k8s.core.v1.Namespace(
        "external-dns",
        metadata={"name": "external-dns"},
        opts=pulumi.ResourceOptions(provider=k8s_provider),
    )

    cert_manager_ns = k8s.core.v1.Namespace(
        "cert-manager",
        metadata={"name": "cert-manager"},
        opts=pulumi.ResourceOptions(provider=k8s_provider),
    )

    annotations = {"eks.amazonaws.role-arn": route53_role.arn} if cloud == "aws" else {}
    k8s.core.v1.ServiceAccount(
        "external-dns-internal",
        metadata={
            "name": "external-dns-internal",
            "namespace": "external-dns",
            "annotations": annotations,
        },
        opts=pulumi.ResourceOptions(
            provider=k8s_provider,
            depends_on=[external_dns_ns],
        ),
    )

    k8s.core.v1.ServiceAccount(
        "cert-manager",
        metadata={
            "name": "cert-manager",
            "namespace": "cert-manager",
            "annotations": annotations,
        },
        opts=pulumi.ResourceOptions(
            provider=k8s_provider,
            depends_on=[cert_manager_ns],
        ),
    )

    return cluster
