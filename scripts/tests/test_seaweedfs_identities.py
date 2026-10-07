"""Offline checks for adding SeaweedFS S3 identities.

python3 -m unittest discover -s scripts/tests -v

Needs sops, age-keygen, jq and PyYAML on PATH (skipped otherwise). Uses a
throwaway age key in a temp directory; no cluster or real secrets involved.
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = (ROOT / 'scripts/bootstrap-secrets.sh').read_text()
FUNCTIONS = [
    'opaque_secret', 'rand_alnum', 'sops_string_data', 'replace_sops_file',
    'seaweedfs_config_file', 'seaweedfs_has_identity', 'seaweedfs_add_identity',
    'create_seaweedfs_client_secret',
]
MISSING = [t for t in ('sops', 'age-keygen', 'jq') if not shutil.which(t)]


def function(name):
    return re.search(r'^function ' + name + r'\(\) \{\n.*?^\}', SCRIPT, re.M | re.S)[0]


@unittest.skipIf(MISSING, 'needs ' + ', '.join(MISSING))
class SeaweedfsIdentities(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        key = self.root / 'age.key'
        out = subprocess.run(['age-keygen', '-o', str(key)], capture_output=True, text=True, check=True)
        self.recipient = re.search(r'age1\w+', out.stderr + out.stdout)[0]
        self.write_sops_config(self.recipient)
        self.env = dict(
            os.environ, ROOT_DIR=str(self.root), ENVIRONMENT='prod',
            SEAWEEDFS_NAMESPACE='seaweedfs',
            # A path, as in the real .env, and exported: sops must not see it.
            SOPS_AGE_KEY=str(key),
        )
        self.env.pop('SOPS_AGE_KEY_FILE', None)
        self.config = self.root / 'platform/services/seaweedfs/secrets/prod/seaweedfs-s3-config.enc.yaml'
        self.seed = {
            'admin': ('ADMINKEY', 'ADMINSECRET'),
            'velero': ('VELEROKEY', 'VELEROSECRET'),
            'forge-db': ('FORGEDBKEY', 'FORGEDBSECRET'),
        }
        config = json.dumps({'identities': [
            {'name': n, 'credentials': [{'accessKey': k, 'secretKey': s}], 'actions': ['Admin']}
            for n, (k, s) in self.seed.items()]}, indent=2)
        # Passed through the environment: the JSON's own quotes would end a
        # bash double-quoted string if it were spliced into the command.
        self.env['SEED_CONFIG'] = '\n'.join('    ' + line for line in config.splitlines())
        self.sh('replace_sops_file "$(seaweedfs_config_file)" "$(opaque_secret seaweedfs seaweedfs-s3-config "  seaweedfs_s3_config: |\n$SEED_CONFIG")"')

    def write_sops_config(self, recipient):
        (self.root / '.sops.yaml').write_text(
            'creation_rules:\n  - path_regex: .*\\.enc\\.yaml$\n    encrypted_regex: "^(data|stringData)$"\n'
            f'    age: {recipient}\n')

    def sh(self, command, check=True):
        body = '\n'.join(function(f) for f in FUNCTIONS)
        return subprocess.run(['bash', '-c', f'set -euo pipefail\n{body}\n{command}'],
                              env=self.env, capture_output=True, text=True, check=check)

    def identities(self):
        out = self.sh(f'sops_string_data "{self.config}" seaweedfs_s3_config').stdout
        return {i['name']: i for i in json.loads(out)['identities']}

    def client_keys(self, path):
        get = lambda k: self.sh(f'sops_string_data "{path}" {k}').stdout.strip()
        return get('access-key-id'), get('secret-access-key')

    def create(self, name='mongo-backup', check=True):
        out_file = self.root / f'platform/services/forge-mongo/secrets/prod/{name}-s3.enc.yaml'
        result = self.sh(f'create_seaweedfs_client_secret {name} {name} forge-mongo {name}-s3 "{out_file}"', check=check)
        return out_file, result

    def test_adds_a_scoped_identity_and_leaves_the_others_alone(self):
        before = self.identities()
        out_file, _ = self.create()
        after = self.identities()
        self.assertEqual(set(after), set(before) | {'mongo-backup'})
        for name in before:
            self.assertEqual(after[name], before[name], f'{name} must be unchanged')
        new = after['mongo-backup']
        self.assertEqual(new['actions'], [f'{a}:mongo-backup' for a in ('Read', 'List', 'Tagging', 'Write')])
        access, secret = self.client_keys(out_file)
        self.assertEqual(new['credentials'], [{'accessKey': access, 'secretKey': secret}])
        self.assertRegex(access, r'^\w{16}$')
        self.assertRegex(secret, r'^\w{32}$')

    def test_nothing_is_written_in_plaintext(self):
        out_file, _ = self.create()
        access, secret = self.client_keys(out_file)
        for path in (out_file, self.config):
            text = path.read_text()
            self.assertIn('ENC[', text)
            for value in (access, secret, 'VELEROSECRET'):
                self.assertNotIn(value, text)
        self.assertEqual(sorted(p.name for p in Path(tempfile.gettempdir()).glob('tmp*.enc.yaml')
                                if p.stat().st_size and self.recipient in p.read_text()), [])

    def test_rerun_changes_nothing(self):
        out_file, _ = self.create()
        config_bytes, file_bytes = self.config.read_bytes(), out_file.read_bytes()
        self.create()
        self.assertEqual(self.config.read_bytes(), config_bytes)
        self.assertEqual(out_file.read_bytes(), file_bytes)

    def test_finishes_an_interrupted_registration(self):
        out_file = self.root / 'platform/services/forge-mongo/secrets/prod/loki-s3.enc.yaml'
        self.sh(f'replace_sops_file "{out_file}" "$(opaque_secret loki s "  access-key-id: KEEPME\n  secret-access-key: KEEPMETOO")"')
        self.create('loki')
        self.assertEqual(self.identities()['loki']['credentials'], [{'accessKey': 'KEEPME', 'secretKey': 'KEEPMETOO'}])

    def test_refuses_when_the_identity_exists_but_its_secret_is_gone(self):
        self.sh('seaweedfs_add_identity orphan orphan K S')
        result = self.create('orphan', check=False)[1]
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('cannot be recovered', result.stderr)
        self.assertEqual(self.identities()['orphan']['credentials'], [{'accessKey': 'K', 'secretKey': 'S'}])

    def test_failed_encryption_leaves_the_config_intact(self):
        before = self.config.read_bytes()
        self.write_sops_config('age1invalidrecipient')
        result = self.create(check=False)[1]
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.config.read_bytes(), before)


if __name__ == '__main__':
    unittest.main()
