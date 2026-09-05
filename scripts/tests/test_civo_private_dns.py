"""Offline checks: python3 -m unittest discover -s scripts/tests -v.

Test-only dependencies: PyYAML and jsonpatch. No cluster or credentials required.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

import jsonpatch
import yaml

ROOT = Path(__file__).resolve().parents[2]
CREATE = (ROOT / 'scripts/create.sh').read_text()
LIB = ROOT / 'scripts/lib/civo-loadbalancers.sh'
DNS = 'external-dns.alpha.kubernetes.io/'


def function(name):
    return re.search(r'^' + name + r'\(\) \{\n.*?^\}', CREATE, re.M | re.S)[0]


def patched_resources():
    overlay = yaml.safe_load((ROOT / 'clusters/single/civo/dev/40-platform-services/kustomization.yaml').read_text())
    paths = [
        'rabbitmq/overlays/dev/rabbitmq.yaml',
        'forge-mongo/overlays/dev/service.yaml',
        'forge-db/overlays/dev/cnpg-cluster.yaml',
        'minio/overlays/dev/ingress-api.yaml',
    ]
    resources = []
    for path in paths:
        resource = yaml.safe_load((ROOT / 'platform/services' / path).read_text())
        for patch in overlay['patches']:
            target = patch['target']
            if target['kind'] == resource['kind'] and target.get('name', resource['metadata']['name']) == resource['metadata']['name']:
                resource = jsonpatch.apply_patch(resource, yaml.safe_load(patch['patch']))
        resources.append(resource)
    return resources


def service_specs(resources):
    rabbit, mongo, db, _ = resources
    template = db['spec']['managed']['services']['additional'][0]['serviceTemplate']
    return [
        (rabbit['spec']['service']['type'], rabbit['spec']['service']['annotations']),
        (mongo['spec']['type'], mongo['metadata']['annotations']),
        (template['spec']['type'], template['metadata']['annotations']),
    ]


class PrivateDnsTests(unittest.TestCase):
    def test_overlay_restores_loadbalancers_and_private_firewall(self):
        resources = patched_resources()
        for service_type, annotations in service_specs(resources):
            self.assertEqual(service_type, 'LoadBalancer')
            self.assertNotIn('metallb.io/address-pool', annotations)
            self.assertEqual(annotations['kubernetes.civo.com/firewall-id'], 'CIVO_PRIVATE_LB_FIREWALL_ID_PLACEHOLDER')
        s3 = resources[3]
        self.assertEqual(s3['metadata']['annotations'][DNS + 'hostname'], 's3-dev.int.aethericforge.ca')
        self.assertEqual(s3['metadata']['annotations'][DNS + 'target'], 'CIVO_PRIVATE_LB_IP_PLACEHOLDER')
        self.assertEqual(s3['spec']['ingressClassName'], 'nginx-private')

    def discover(self, response, missing_service=False):
        script = f'''set -euo pipefail
source "{LIB}"
kubectl() {{ printf '%s' '{'' if missing_service else 'lb-id'}'; }}
curl() {{ printf '%s' "$RESPONSE"; }}
sleep() {{ :; }}
civo_private_service_ip rabbitmq rabbitmq
'''
        return subprocess.run(['bash', '-c', script], text=True, capture_output=True, env={**os.environ, 'CIVO_TOKEN': 'test-only', 'NETWORK_CIDR': '10.60.0.0/24', 'RESPONSE': response})

    def test_private_ip_selected_over_public_ip(self):
        result = self.discover(json.dumps({'private_ip': '10.60.0.12', 'public_ip': '212.2.247.192'}))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), '10.60.0.12')

    def test_invalid_or_missing_private_addresses_never_fall_back(self):
        for address in ['212.2.247.192', '10.61.0.12', 'garbage', 'fd00::1', None]:
            with self.subTest(address=address):
                result = self.discover(json.dumps({'private_ip': address, 'public_ip': '212.2.247.192'}))
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, '')
        self.assertNotEqual(self.discover('not-json').returncode, 0)
        self.assertNotEqual(self.discover('{}', missing_service=True).returncode, 0)

    def run_deploy(self, fail_discovery=False):
        with tempfile.TemporaryDirectory() as tmp:
            fixture = Path(tmp) / 'fixture.yaml'
            fixture.write_text(yaml.safe_dump_all(patched_resources()))
            script = '\n'.join(function(name) for name in ['log', 'fail', 'replace_civo_placeholder', 'render_overlay', 'deploy_platform_services'])
            script += '''
render_checked() { cp fixture.yaml "$2"; }
apply_rendered() { count=$((count+1)); cp "$1" "applied-$count.yaml"; }
civo_private_service_ip() {
  case "$1" in
    rabbitmq) echo 10.60.0.12 ;;
    forge-mongo) if [[ "$FAIL_DISCOVERY" == 1 ]]; then return 1; fi; echo 10.60.0.13 ;;
    forge-db) echo 10.60.0.14 ;;
  esac
}
count=0
deploy_platform_services
'''
            env = {**os.environ, 'CLOUD': 'civo', 'CLUSTER_DEPLOYMENT_ROOT': '/unused', 'WIREGUARD_PRIVATE_IP': '10.60.0.2', 'INT_DNS_HOST': '10.60.0.2', 'WIREGUARD__LOCAL_CIDRS': '192.168.1.0/24', 'PRIVATE_LB_FIREWALL_ID': 'private-firewall', 'INTERNAL_DOMAIN': 'int.aethericforge.ca', 'EXTERNAL_DOMAIN': 'aethericforge.ca', 'ENVIRONMENT': 'dev', 'CIVO_PRIVATE_LB_IP': '10.60.0.9', 'CIVO_PUBLIC_LB_IP': '212.2.247.176', 'FAIL_DISCOVERY': str(int(fail_discovery))}
            for name in ['WIREGUARD_PRIVATE_IP', 'WIREGUARD__LOCAL_CIDRS', 'INT_DNS_HOST']:
                env.pop(name, None)
            result = subprocess.run(['bash', '-euc', script], cwd=tmp, env=env, capture_output=True, text=True)
            applied = [list(yaml.safe_load_all(p.read_text())) for p in sorted(Path(tmp).glob('applied-*.yaml'))]
            return result, applied

    def test_two_pass_publication_and_operator_templates(self):
        result, applied = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(applied), 2)
        for _, annotations in service_specs(applied[0]):
            self.assertEqual(annotations[DNS + 'controller'], 'awaiting-private-ip')
        for (_, annotations), ip in zip(service_specs(applied[1]), ['10.60.0.12', '10.60.0.13', '10.60.0.14']):
            self.assertEqual(annotations[DNS + 'target'], ip)
            self.assertEqual(annotations[DNS + 'controller'], 'dns-controller')
            self.assertEqual(annotations['kubernetes.civo.com/firewall-id'], 'private-firewall')
        self.assertEqual(applied[1][3]['metadata']['annotations'][DNS + 'target'], '10.60.0.9')

    def test_placeholder_requires_config_only_when_used(self):
        with tempfile.TemporaryDirectory() as tmp:
            fixture = Path(tmp) / 'route.yaml'
            script = function('fail') + '\n' + function('replace_civo_placeholder')
            script += '\nunset WIREGUARD__LOCAL_CIDRS\nreplace_civo_placeholder route.yaml WIREGUARD_LOCAL_CIDR_PLACEHOLDER WIREGUARD__LOCAL_CIDRS'
            fixture.write_text('route: WIREGUARD_LOCAL_CIDR_PLACEHOLDER\n')
            result = subprocess.run(['bash', '-euc', script], cwd=tmp, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Missing WIREGUARD__LOCAL_CIDRS', result.stdout)
            script = function('fail') + '\n' + function('replace_civo_placeholder')
            script += '\nWIREGUARD__LOCAL_CIDRS=192.168.1.0/24\nreplace_civo_placeholder route.yaml WIREGUARD_LOCAL_CIDR_PLACEHOLDER WIREGUARD__LOCAL_CIDRS'
            result = subprocess.run(['bash', '-euc', script], cwd=tmp, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(fixture.read_text(), 'route: 192.168.1.0/24\n')

    def test_adoption_contains_only_reported_fields(self):
        resources = patched_resources()
        resources.append({'apiVersion': 'v1', 'kind': 'Secret', 'metadata': {'name': 'unrelated'}, 'data': {'token': 'must-not-copy'}})
        helper = ROOT / 'scripts/lib/civo-service-adoption.py'
        # kubectl versions can emit a List or a stream of individual objects.
        for payload in [json.dumps({'kind': 'List', 'items': resources}), '\n'.join(map(json.dumps, resources))]:
            result = subprocess.run(['python3', str(helper)], input=payload, text=True, capture_output=True, check=True)
            items = json.loads(result.stdout)['items']
            self.assertEqual(len(items), 2)
            mongo = next(i for i in items if i['kind'] == 'Service')
            self.assertEqual(set(mongo), {'apiVersion', 'kind', 'metadata'})
            self.assertEqual(set(mongo['metadata']['annotations']), {'kubernetes.civo.com/firewall-id'})
            db = next(i for i in items if i['kind'] == 'Cluster')
            self.assertEqual(set(db['spec']), {'managed'})
            self.assertEqual(set(db['spec']['managed']['services']), {'additional'})
            self.assertNotIn('must-not-copy', result.stdout)
            release = subprocess.run(['python3', str(helper), '--release'], input=result.stdout, text=True, capture_output=True, check=True)
            for item in json.loads(release.stdout)['items']:
                self.assertEqual(set(item), {'apiVersion', 'kind', 'metadata'})
                self.assertEqual(set(item['metadata']), {'name', 'namespace'})

    def test_adoption_force_is_scoped_and_temporary(self):
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / 'fixture.json').write_text(json.dumps({'kind': 'List', 'items': patched_resources()}))
            script = '\n'.join(function(name) for name in ['log', 'fail', 'apply_rendered'])
            script += r"""
kubectl() {
  if [[ "$1" == create ]]; then cat fixture.json; return; fi
  printf '%s\n' "$*" >> commands.txt
  if [[ "${!#}" == '-' ]]; then cat >> fragments.json; fi
}
apply_rendered rendered.yaml platform-services
"""
            result = subprocess.run(['bash', '-euo', 'pipefail', '-c', script], cwd=tmp, text=True, capture_output=True,
                                    env={**os.environ, 'CLOUD': 'civo', 'CIVO_ADOPT_SERVICE_FIELDS': 'true', 'SCRIPTS_DIR': str(ROOT / 'scripts')})
            self.assertEqual(result.returncode, 0, result.stderr)
            commands = (Path(tmp) / 'commands.txt').read_text().splitlines()
            self.assertEqual(len(commands), 3)
            self.assertIn('--force-conflicts --field-manager=forge-service-migration', commands[0])
            self.assertIn('--validate=false', commands[0])
            self.assertIn('--validate=false', commands[2])
            self.assertEqual(commands[1], 'apply --server-side -f rendered.yaml')
            self.assertNotIn('--force-conflicts', commands[2])
            self.assertIn('--field-manager=forge-service-migration', commands[2])

    def test_discovery_failure_does_not_enable_dns(self):
        result, applied = self.run_deploy(fail_discovery=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(applied), 1)
        for _, annotations in service_specs(applied[0]):
            self.assertEqual(annotations[DNS + 'controller'], 'awaiting-private-ip')


if __name__ == '__main__':
    unittest.main()
