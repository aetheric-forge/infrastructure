from typing import List

from pydantic import BaseModel, field_validator
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

class GCPConfig(BaseModel):
    project: str
    region: str
    zone: str
    vpc_cidr: str
    node_desired: int
    node_min: int
    node_max: int
    k8s_version: str
    machine_type: str

class WireguardConfig(BaseModel):
    enabled: bool = False
    ssh_key_name: str | None = None
    ssh_public_key_file: str | None = None
    tunnel_cidr: str | None = None
    access_cidrs: List[str] | None = None
    local_cidrs: List[str] | None = None

    @field_validator("access_cidrs", "local_cidrs", mode="before")
    @classmethod
    def _split_comma_separated(cls, v):
        # configure.sh writes these as a plain (possibly comma-separated)
        # string, not JSON-array syntax, so pydantic-settings won't split
        # it into a list on its own.
        if isinstance(v, str):
            return [cidr.strip() for cidr in v.split(",") if cidr.strip()]
        return v

class Config(BaseSettings):
    environment: str
    cloud: str

    org_name: str
    system_name: str

    base_domain: str
    internal_domain: str

    aws: AWSConfig | None = None
    gcp: GCPConfig | None = None
    wireguard: WireguardConfig | None = None

    model_config = SettingsConfigDict(
        env_file=".env",
        env_nested_delimiter="__",
    )

def prefix(cfg: Config) -> str:
    return f"{cfg.org_name}-{cfg.system_name}-{cfg.environment}"

def load_config() -> Config:
    return Config() # pyright: ignore[reportCallIssue]
