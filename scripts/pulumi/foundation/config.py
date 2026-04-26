import os
from dataclasses import dataclass
from typing import List


def _split(v: str) -> List[str]:
    return [x.strip() for x in v.split(",") if x.strip()]


@dataclass
class Config:
    env: str
    org: str
    system: str
    region: str

    base_domain: str
    internal_domain: str
    external_domain: str

    is_public_cluster: bool
    kube_api_cidrs: List[str]

    k8s_version: str
    node_arch: str
    node_desired: int
    node_min: int
    node_max: int

    wg_enabled: bool
    wg_tunnel_cidr: str
    wg_access_cidrs: List[str]
    wg_local_cidrs: List[str]
    wg_ssh_key_name: str
    wg_ssh_public_key_file: str


def load_config() -> Config:
    return Config(
        env=os.environ["ENVIRONMENT"],
        org=os.environ["ORG_NAME"],
        system=os.environ["SYSTEM_NAME"],
        region=os.environ["AWS_REGION"],
        base_domain=os.environ["BASE_DOMAIN"],
        internal_domain=os.environ["INTERNAL_DOMAIN"],
        external_domain=os.environ["EXTERNAL_DOMAIN"],
        is_public_cluster=(os.environ["CLUSTER_PUBLIC_ACCESS"] == "true"),
        kube_api_cidrs=_split(os.environ["KUBE_API_PUBLIC_ACCESS_CIDRS"])
        if "KUBE_API_PUBLIC_ACCESS_CIDRS" in os.environ
        else [],
        k8s_version=os.environ["K8S_VERSION"],
        node_arch=os.environ["NODE_ARCH"],
        node_desired=int(os.environ["NODE_DESIRED_SIZE"]),
        node_min=int(os.environ["NODE_MIN_SIZE"]),
        node_max=int(os.environ["NODE_MAX_SIZE"]),
        wg_enabled=os.environ["WIREGUARD_ENABLED"] == "true",
        wg_ssh_key_name=os.environ["WIREGUARD_SSH_KEY_NAME"],
        wg_ssh_public_key_file=os.environ["WIREGUARD_SSH_PUBLIC_KEY_FILE"],
        wg_tunnel_cidr=os.environ["WIREGUARD_TUNNEL_CIDR"],
        wg_access_cidrs=_split(os.environ["WIREGUARD_ACCESS_CIDRS"]),
        wg_local_cidrs=_split(os.environ["WIREGUARD_LOCAL_CIDRS"]),
    )


def prefix(cfg: Config) -> str:
    return f"{cfg.org}-{cfg.system}-{cfg.env}"
