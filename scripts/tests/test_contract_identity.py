"""Unit fixtures compiled Client identity vs resolved exact Git SDK cache."""

import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from test_ci import CI


class ContractIdentityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.module = root / "app"
        self.sdk = root / "cache/client/api/dart"
        self.sdk.mkdir(parents=True)
        (self.sdk / "sdk.txt").write_text("fixture-sdk", encoding="utf-8")
        self.descriptor = self.sdk.parent / "client.binpb"
        self.descriptor.write_bytes(b"fixture-descriptor")
        self.digest = hashlib.sha256(self.descriptor.read_bytes()).hexdigest()
        git = self.sdk.parent.parent
        for args in (["init", "--initial-branch=main"], ["config", "user.email", "fixture@example.invalid"],
                     ["config", "user.name", "Fixture"], ["add", "api"], ["commit", "-m", "fixture"]):
            subprocess.run(["git", *args], cwd=git, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=git, text=True).strip()
        (self.module / "lib/client").mkdir(parents=True)
        (self.module / "lib/client/contract_identity.dart").write_text(
            f"const clientApiRevision = '{self.revision}';\nconst clientContractSha256 = '{self.digest}';\n",
            encoding="utf-8")
        (self.module / "pubspec.yaml").write_text(f"      ref: {self.revision}\n", encoding="utf-8")
        (self.module / "pubspec.lock").write_text(
            "packages:\n  endlessnet_client_api:\n    description:\n      path: \"api/dart\"\n"
            f"      ref: \"{self.revision}\"\n      resolved-ref: \"{self.revision}\"\n"
            "    source: git\nsdks:\n", encoding="utf-8")
        (self.module / ".dart_tool").mkdir()
        (self.module / ".dart_tool/package_config.json").write_text(json.dumps({
            "packages": [{"name": "endlessnet_client_api", "rootUri": self.sdk.as_uri() + "/"}]
        }), encoding="utf-8")
        printer = patch.object(CI, "print", create=True)
        printer.start()
        self.addCleanup(printer.stop)

    def test_exact_clean_sdk_descriptor_matches_compiled_identity(self):
        CI.verify_client_contract(self.module)

    def test_modified_cached_sdk_is_not_exact_producer_source(self):
        (self.sdk / "sdk.txt").write_text("modified", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "exact producer"):
            CI.verify_client_contract(self.module)

    def test_changed_descriptor_cannot_keep_the_compiled_digest(self):
        self.descriptor.write_bytes(b"other-descriptor")
        with self.assertRaisesRegex(ValueError, "published descriptor"):
            CI.verify_client_contract(self.module)

    def test_resolved_ref_drift_and_override_fail_before_cache_use(self):
        lock = self.module / "pubspec.lock"
        lock.write_text(lock.read_text(encoding="utf-8").replace(
            f'resolved-ref: "{self.revision}"', 'resolved-ref: "' + "0" * 40 + '"'), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "lock"):
            CI.verify_client_contract(self.module)
        with (self.module / "pubspec.yaml").open("a", encoding="utf-8") as stream:
            stream.write("dependency_overrides:\n")
        with self.assertRaisesRegex(ValueError, "manifest"):
            CI.verify_client_contract(self.module)
