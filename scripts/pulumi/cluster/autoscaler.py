import pulumi
import pulumi_aws as aws
import pulumi_kubernetes as k8s


def install_autoscaler(cluster, cluster_name: str, region: str):
    # --- OIDC provider from EKS cluster ---
    oidc_provider = cluster.core.oidc_provider

    # --- IAM role for IRSA ---
    assume_role_policy = pulumi.Output.all(
        oidc_provider.url,
        oidc_provider.arn,
    ).apply(
        lambda args: (
            aws.iam.get_policy_document(
                statements=[
                    {
                        "effect": "Allow",
                        "actions": ["sts:AssumeRoleWithWebIdentity"],
                        "principals": [
                            {
                                "type": "Federated",
                                "identifiers": [args[1]],
                            }
                        ],
                        "conditions": [
                            {
                                "test": "StringEquals",
                                "variable": f"{args[0].replace('https://', '')}:sub",
                                "values": [
                                    "system:serviceaccount:kube-system:cluster-autoscaler"
                                ],
                            }
                        ],
                    }
                ]
            ).json
        )
    )

    autoscaler_role = aws.iam.Role(
        f"{cluster_name}-cluster-autoscaler-role",
        assume_role_policy=assume_role_policy,
    )

    # --- IAM policy ---
    autoscaler_policy = aws.iam.Policy(
        f"{cluster_name}-cluster-autoscaler-policy",
        policy="""
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "ec2:DescribeLaunchTemplateVersions"
      ],
      "Resource": "*"
    }
  ]
}
""",
    )

    aws.iam.RolePolicyAttachment(
        f"{cluster_name}-cluster-autoscaler-attach",
        role=autoscaler_role.name,
        policy_arn=autoscaler_policy.arn,
    )

    # --- Kubernetes provider ---
    k8s_provider = k8s.Provider(
        "autoscaler-k8s-provider",
        kubeconfig=cluster.kubeconfig,
    )

    # --- ServiceAccount (IRSA binding) ---
    service_account = k8s.core.v1.ServiceAccount(
        "cluster-autoscaler-sa",
        metadata={
            "name": "cluster-autoscaler",
            "namespace": "kube-system",
            "annotations": {
                "eks.amazonaws.com/role-arn": autoscaler_role.arn,
            },
        },
        opts=pulumi.ResourceOptions(provider=k8s_provider),
    )

    # --- Helm deployment ---
    autoscaler = k8s.helm.v3.Release(
        "cluster-autoscaler",
        chart="cluster-autoscaler",
        repository_opts={
            "repo": "https://kubernetes.github.io/autoscaler",
        },
        namespace="kube-system",
        values={
            "image": {
                "tag": "v1.34.0",
            },
            "autoDiscovery": {
                "clusterName": cluster_name,
            },
            "awsRegion": region,
            "rbac": {
                "create": True,
                "serviceAccount": {
                    "create": False,
                    "name": "cluster-autoscaler",
                },
            },
            "extraArgs": {
                "balance-similar-node-groups": "true",
                "skip-nodes-with-system-pods": "false",
                "skip-nodes-with-local-storage": "false",
            },
        },
        opts=pulumi.ResourceOptions(
            provider=k8s_provider,
            depends_on=[service_account],
        ),
    )

    return autoscaler
