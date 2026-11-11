"""MSI ownership and upgrade invariants without installing on the test host."""

import importlib.util
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

from test_ci import CI

SOURCE = Path(__file__).resolve().parents[1] / "windows_installer.py"
SPEC = importlib.util.spec_from_file_location("windows_installer", SOURCE)
INSTALLER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(INSTALLER)
NS = {"w": INSTALLER.NS}


class WindowsInstallerTests(unittest.TestCase):
    def test_tag_build_uses_release_version_in_the_ui_executable(self):
        self.assertEqual(CI.windows_version_arguments({"GITHUB_REF": "refs/tags/v0.4.2"}), ["--build-name=0.4.2"])
        self.assertEqual(CI.windows_version_arguments({"GITHUB_REF": "refs/heads/main"}), [])
        with self.assertRaises(ValueError):
            CI.windows_version_arguments({"GITHUB_REF": "refs/tags/v1.0.0"})

    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.ui, self.client = self.root / "ui", self.root / "client"
        self.ui.mkdir()
        self.client.mkdir()
        (self.ui / "endlessnet_client_ui.exe").write_bytes(b"fixture-ui")
        for name in ("client.exe", "wintun.dll", "WINTUN-LICENSE.txt"):
            (self.client / name).write_bytes(b"fixture-client")
        self.actions = self.root / "actions.dll"
        self.actions.write_bytes(b"fixture-actions")
        self.service = {"ENDLESSNET_CLIENT_DEFAULT_PROFILE_ID": "fixture-profile",
                        "ENDLESSNET_CLIENT_CONTROL_ORIGIN": "https://control.invalid"}
        self.policy = {"schema": 1, "profile_id": "fixture-profile",
                       "control_origin": "https://control.invalid"}

    def render(self, version="0.1.0"):
        return ET.parse(INSTALLER.render(self.ui, self.client, self.service,
                        self.policy, self.actions, version, self.root / "output"))

    def test_service_registry_and_initialization_order(self):
        tree = self.render()
        service = tree.find(".//w:ServiceInstall", NS)
        self.assertEqual((service.get("Account"), service.get("Start"), service.get("Arguments")),
                         ("LocalSystem", "auto", "installed-run"))
        control = tree.find(".//w:ServiceControl", NS)
        self.assertEqual((control.get("Start"), control.get("Stop"), control.get("Remove")),
                         ("install", "both", "uninstall"))
        self.assertEqual(tree.find(".//w:WriteRegistryValues", NS).get("Sequence"), "5810")
        init = tree.find(".//w:CustomAction[@Id='InitializeState']", NS)
        self.assertEqual((init.get("Execute"), init.get("Impersonate"), init.get("Return")),
                         ("deferred", "no", "check"))
        condition = tree.find(".//w:Custom[@Action='InitializeState']", NS)
        self.assertEqual(condition.get("After"), "WriteRegistryValues")
        self.assertIn("NOT ENDLESSNET_EXISTING_INSTALLATION", condition.get("Condition"))

    def test_upgrade_keeps_identity_policy_and_private_state(self):
        tree = self.render()
        self.assertEqual(tree.find(".//w:Package", NS).get("UpgradeCode"), INSTALLER.UPGRADE_CODE)
        self.assertEqual(tree.find(".//w:MajorUpgrade", NS).get("Schedule"), "afterInstallInitialize")
        policy = tree.find(".//w:File[@Id='LaunchPolicy']/..", NS)
        self.assertEqual((policy.get("Permanent"), policy.get("NeverOverwrite")), ("yes", "yes"))
        identity = tree.find(".//w:RegistryValue[@Name='InstallationId']/..", NS)
        self.assertEqual(identity.get("Permanent"), "yes")
        state = tree.find(".//w:Directory[@Id='ClientState']//w:PermissionEx", NS)
        self.assertEqual(state.get("Sddl"), INSTALLER.PRIVATE)
        self.assertNotIn(";;;BU)", state.get("Sddl"))
        first_guids = [node.get("Guid") for node in tree.findall(".//w:Component", NS)]
        next_guids = [node.get("Guid") for node in self.render("0.1.1").findall(".//w:Component", NS)]
        self.assertEqual(first_guids, next_guids)

    def test_conflicting_inputs_and_absent_runtime_are_rejected(self):
        (self.ui / "CLIENT.EXE").write_bytes(b"conflict")
        with self.assertRaisesRegex(ValueError, "Конфликт"):
            self.render()
        (self.ui / "CLIENT.EXE").unlink()
        (self.client / "wintun.dll").unlink()
        with self.assertRaisesRegex(ValueError, "runtime"):
            self.render()

    def test_policy_and_literal_values(self):
        self.service["ENDLESSNET_CLIENT_PROFILE_DISPLAY_NAME"] = "$(name)[value]"
        tree = self.render()
        values = [node.get("Value") for node in tree.findall(".//w:MultiStringValue", NS)]
        self.assertIn(r"ENDLESSNET_CLIENT_PROFILE_DISPLAY_NAME=$$(name)[\[]value[\]]", values)
        self.policy["instance_id"] = "stale-runtime"
        with self.assertRaisesRegex(ValueError, "instance_id"):
            self.render()


if __name__ == "__main__":
    unittest.main()
