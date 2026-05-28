import pulumi
import os
from kubernetes import create_cluster
from secrets import create_secrets


def must(name: str) -> str:
    v = os.getenv(name)
    if not v:
        raise Exception(f"Missing required env: {name}")
    return v


org = must("ORG_NAME")
system = must("SYSTEM_NAME")
env = must("ENVIRONMENT")
cloud = os.getenv("CLOUD", "local")
cluster_name = f"{org}-{system}-{env}"

print(f"Using cloud environment: {cloud}")

cluster = create_cluster()
create_secrets()

if cloud == "aws":
    region = must("AWS_REGION")
    from autoscaler import install_autoscaler
    from csi import install_ebs_csi

    install_ebs_csi(cluster_name, cluster)
    install_autoscaler(cluster, cluster_name, region)

    pulumi.export("kubeconfig", pulumi.Output.secret(cluster.kubeconfig))
