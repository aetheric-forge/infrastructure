import pulumi
import pulumi_aws as aws
import pulumi_eks as eks


def install_ebs_csi(cluster_name: str, cluster: eks.Cluster):
    oidc = cluster.core.oidc_provider

    assume_role_policy = pulumi.Output.all(
        oidc.url,
        oidc.arn,
    ).apply(
        lambda args: (
            f"""
{{
  "Version": "2012-10-17",
  "Statement": [
    {{
      "Effect": "Allow",
      "Principal": {{
        "Federated": "{args[1]}"
      }},
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {{
        "StringEquals": {{
          "{args[0]}:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }}
      }}
    }}
  ]
}}
"""
        )
    )

    role = aws.iam.Role(
        f"{cluster_name}-ebs-csi-role",
        assume_role_policy=assume_role_policy,
    )

    aws.iam.RolePolicyAttachment(
        f"{cluster_name}-ebs-csi-policy",
        role=role.name,
        policy_arn="arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy",
    )

    aws.eks.Addon(
        f"{cluster_name}-ebs-csi",
        cluster_name=cluster_name,
        addon_name="aws-ebs-csi-driver",
        service_account_role_arn=role.arn,
    )
