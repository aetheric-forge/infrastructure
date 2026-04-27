import pulumi
import os
from eks import create_cluster
from csi import install_ebs_csi
from autoscaler import install_autoscaler


def must(name: str) -> str:
    v = os.getenv(name)
    if not v:
        raise Exception(f"Missing required env: {name}")
    return v


org = must("ORG_NAME")
system = must("SYSTEM_NAME")
env = must("ENVIRONMENT")
region = must("AWS_REGION")
cluster_name = f"{org}-{system}-{env}"

cluster = create_cluster()

install_ebs_csi(cluster_name, cluster)

install_autoscaler(cluster, cluster_name, region)

pulumi.export("kubeconfig", pulumi.Output.secret(cluster.kubeconfig))

