from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
CONFIGURE = (ROOT / "scripts/configure.sh").read_text()
CREATE = (ROOT / "scripts/create.sh").read_text()
AWS_WIREGUARD = (ROOT / "scripts/wireguard/setup.sh").read_text()
CLUSTER_MAIN = (ROOT / "scripts/pulumi/cluster/__main__.py").read_text()
CLUSTER = (ROOT / "scripts/pulumi/cluster/kubernetes.py").read_text()


class BootstrapConfigurationTests(unittest.TestCase):
    def test_configurator_writes_canonical_aws_names(self):
        self.assertIn('echo "AWS__REGION=$AWS__REGION"', CONFIGURE)
        self.assertIn('AWS__NODE_MIN_SIZE=$(prompt "AWS__NODE_MIN_SIZE"', CONFIGURE)
        self.assertNotIn('AWS_REGION" >>', CONFIGURE)
        self.assertNotIn('AWS_NODE_MIN_SIZE=$(prompt', CONFIGURE)

    def test_optional_prompt_returns_its_value(self):
        function = CONFIGURE.split('prompt_optional() {', 1)[1].split('\n}', 1)[0]
        self.assertIn('echo "$value"', function)
        self.assertNotIn('die ', CONFIGURE)

    def test_wireguard_enablement_uses_nested_env_name(self):
        self.assertIn('${WIREGUARD__ENABLED:-}', CREATE)
        self.assertIn('${WIREGUARD__ENABLED:-false}', AWS_WIREGUARD)
        self.assertNotIn('${WIREGUARD_ENABLED', CREATE)
        self.assertNotIn('${WIREGUARD_ENABLED', AWS_WIREGUARD)

    def test_aws_cluster_consumes_configured_env_names(self):
        for name in (
            'AWS__REGION',
            'AWS__NODE_MIN_SIZE',
            'AWS__NODE_MAX_SIZE',
            'AWS__NODE_DESIRED_SIZE',
            'AWS__NODE_ARCH',
            'AWS__K8S_VERSION',
        ):
            self.assertIn(name, CLUSTER_MAIN + CLUSTER)
        self.assertIn('{"arm", "arm64", "aarch64"}', CLUSTER)

    def test_aws_wireguard_uses_configured_networks(self):
        self.assertIn('WIREGUARD__TUNNEL_CIDR', AWS_WIREGUARD)
        self.assertIn('$AWS__VPC_CIDR', AWS_WIREGUARD)
        self.assertIn('$WIREGUARD__LOCAL_CIDRS', AWS_WIREGUARD)

    def test_civo_gateway_honors_wireguard_enablement(self):
        self.assertIn(
            'if os.getenv("WIREGUARD__ENABLED", "false").lower() == "true":',
            CLUSTER,
        )


if __name__ == "__main__":
    unittest.main()
