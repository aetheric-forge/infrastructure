import pulumi
import pulumi_aws as aws

config = pulumi.Config("bootstrap")
prefix = f"{config.require("orgName")}-{config.require("systemName")}-{config.require("environment")}"

internal_domain = config.require("internalDomainName")
external_domain = config.require("externalDomainName")


def create_zones(vpc_id: str):
    # 🧠 Private hosted zone (internal)
    private_zone = aws.route53.Zone(
        f"{prefix}-internal-zone",
        name=internal_domain,
        vpcs=[{
            "vpc_id": vpc_id,
        }],
        comment="Internal zone for Aetheric Forge",
    )

    # 🌐 Public hosted zone (external)
    public_zone = aws.route53.Zone(
        f"{prefix}-external-zone",
        name=external_domain,
        comment="Public zone for Aetheric Forge",
    )

    pulumi.export("internalZoneId", private_zone.zone_id)
    pulumi.export("externalZoneId", public_zone.zone_id)

    return {
        "internal": private_zone,
        "external": public_zone,
    }
