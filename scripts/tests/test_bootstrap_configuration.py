from pathlib import Path
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[2]
CONFIGURE = (ROOT / "scripts/configure.sh").read_text()
CREATE = (ROOT / "scripts/create.sh").read_text()
AWS_WIREGUARD = (ROOT / "scripts/wireguard/setup.sh").read_text()
CLUSTER_MAIN = (ROOT / "scripts/pulumi/cluster/__main__.py").read_text()
CLUSTER = (ROOT / "scripts/pulumi/cluster/kubernetes.py").read_text()
STEP_CA = (ROOT / "platform/core/step-ca/base/deployment.yaml").read_text()
CERT_MANAGER = (ROOT / "platform/core/cert-manager/base/kustomization.yaml").read_text()
GENERATE_VALUES = (ROOT / "scripts/generate-values.sh").read_text()
MINIO_BOOTSTRAP = yaml.safe_load(
    (ROOT / "platform/services/minio/base/bootstrap-admin-policy-job.yaml").read_text()
)


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

    def test_aws_wireguard_discovers_and_persists_vpc_interface(self):
        self.assertIn("VPC_INTERFACE=\\$(ip route show default", AWS_WIREGUARD)
        self.assertIn('test -n "\\$VPC_INTERFACE"', AWS_WIREGUARD)
        self.assertIn('PostUp = ', AWS_WIREGUARD)
        self.assertIn('PostDown = ', AWS_WIREGUARD)
        self.assertNotIn('ens5', AWS_WIREGUARD)

    def test_civo_gateway_honors_wireguard_enablement(self):
        self.assertIn(
            'if os.getenv("WIREGUARD__ENABLED", "false").lower() == "true":',
            CLUSTER,
        )

    def test_internal_dns_host_is_not_embedded_in_shared_components(self):
        self.assertIn('--resolver=INT_DNS_HOST_PLACEHOLDER:5335', STEP_CA)
        self.assertIn(
            '--dns01-recursive-nameservers=INT_DNS_HOST_PLACEHOLDER:5335',
            CERT_MANAGER,
        )
        self.assertNotIn('192.168.1.1', STEP_CA + CERT_MANAGER)
        self.assertIn(
            'replace_civo_placeholder "$rendered" INT_DNS_HOST_PLACEHOLDER INT_DNS_HOST',
            CREATE,
        )

    def test_external_dns_exclusion_uses_configured_domain(self):
        self.assertIn('--exclude-domains=${INTERNAL_DOMAIN}', GENERATE_VALUES)
        self.assertNotIn('--exclude-domains=int.aethericforge.ca', GENERATE_VALUES)

    def test_minio_policy_bootstrap_is_bounded_and_reports_failures(self):
        self.assertEqual(MINIO_BOOTSTRAP['spec']['activeDeadlineSeconds'], 660)
        container = MINIO_BOOTSTRAP['spec']['template']['spec']['containers'][0]
        self.assertEqual(
            container['image'],
            'quay.io/minio/mc:RELEASE.2025-08-13T08-35-41Z',
        )
        script = container['command'][-1]
        self.assertNotIn('sleep 600', script)
        self.assertNotIn('/policies/minio-admins.json || true', script)
        self.assertIn('MinIO did not become ready within 600 seconds', script)


if __name__ == "__main__":
    unittest.main()
