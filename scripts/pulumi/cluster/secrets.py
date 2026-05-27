import os
from pulumi_command import local
import pulumi
import pulumi_kubernetes as k8s


ARGOCD_NAMESPACE = "argocd"


def _require_env(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise ValueError(f"Missing required env var: {name}")
    return value


def create_sops_age_secret(namespace: k8s.core.v1.Namespace):
    return k8s.core.v1.Secret(
        "sops-age",
        metadata={
            "name": "sops-age",
            "namespace": namespace,
        },
        string_data={
            "keys.txt": _require_env("SOPS_AGE_KEY"),
        },
        type="Opaque",
        opts=pulumi.ResourceOptions(
            additional_secret_outputs=["data", "stringData"],
            depends_on=[namespace],
        ),
    )


def create_repo_git_ssh_secret(namespace: k8s.core.v1.Namespace):
    return k8s.core.v1.Secret(
        "repo-git-ssh",
        metadata={
            "name": "repo-git-ssh",
            "namespace": namespace,
            "labels": {
                "argocd.argoproj.io/secret-type": "repository",
            },
        },
        string_data={
            "type": "git",
            "url": _require_env("GIT_REPO_URL"),
            "sshPrivateKey": _require_env("SSH_REPO_KEY"),
        },
        type="Opaque",
        opts=pulumi.ResourceOptions(
            additional_secret_outputs=["data", "stringData"],
            depends_on=[namespace],
        ),
    )


def create_secrets(namespace: str = ARGOCD_NAMESPACE):
    ns = k8s.core.v1.Namespace(
        namespace,
        metadata={
            "name": namespace,
        }
    )
    return {
        "sops_age": create_sops_age_secret(ns),
        "repo_git_ssh": create_repo_git_ssh_secret(ns),
    }


wait_for_cluster = local.Command(
    "wait-for-cluster",
    create="""
    for i in $(seq 1 60); do
      kubectl get nodes && exit 0
      echo "waiting for cluster..."
      sleep 10
    done
    echo "cluster never became ready"
    exit 1
    """,
)
