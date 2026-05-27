from typing import List

from pydantic import BaseModel
from pydantic_settings import BaseSettings, SettingsConfigDict

class AWSConfig(BaseModel):
    region: str
    vpc_cidr: str
    node_desired: int
    node_min: int
    node_max: int
    k8s_version: str
    node_size: str
    is_public_cluster: bool
    kube_api_cidrs: list[str]

class WireguardConfig(BaseModel):
    enabled: bool = False
    ssh_key_name: str | None = None
    ssh_public_key_file: str | None = None
    tunnel_cidr: str | None = None
    access_cidrs: List[str] | None = None
    local_cidrs: List[str] | None = None

class Config(BaseSettings):
    environment: str
    cloud: str

    org_name: str
    system_name: str

    base_domain: str
    internal_domain: str

    aws: AWSConfig | None = None
    wireguard: WireguardConfig | None = None

    model_config = SettingsConfigDict(
        env_file=".env",
        env_nested_delimiter="__",
    )

def prefix(cfg: Config) -> str:
    return f"{cfg.org_name}-{cfg.system_name}-{cfg.environment}"

def load_config() -> Config:
    return Config() # pyright: ignore[reportCallIssue]
