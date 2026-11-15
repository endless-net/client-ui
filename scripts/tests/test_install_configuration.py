import importlib.util
from pathlib import Path
import tempfile
import unittest
import uuid

SPEC = importlib.util.spec_from_file_location("install_configuration", Path(__file__).resolve().parents[1] / "install_configuration.py")
CONFIG = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CONFIG)


class InstallConfigurationTests(unittest.TestCase):
    def configure(self, server="https://endlessnet.ru", endpoint="192.168.1.10:51820"):
        with tempfile.TemporaryDirectory() as output:
            return CONFIG.configure({"ENDLESSNET_CLIENT_CONNECTION_LISTEN_PORT": "51820"}, server,
                                    endpoint, "S-1-5-21-1-2-3-1000", r"C:\ProgramData\EndlessNet\Client\state", output)

    def test_one_server_makes_matching_profiles_without_persisted_instance(self):
        service, policy = self.configure()
        self.assertEqual(service["ENDLESSNET_CLIENT_CONTROL_ORIGIN"], "https://api.endlessnet.ru")
        self.assertEqual(service["ENDLESSNET_CLIENT_DEFAULT_PROFILE_ID"], policy["profile_id"])
        self.assertEqual(policy["control_origin"], "https://api.endlessnet.ru")
        self.assertNotIn("instance_id", policy)
        uuid.UUID(service["ENDLESSNET_CLIENT_INSTALLATION_ID"])
        self.assertEqual(self.configure()[1]["profile_id"], policy["profile_id"])

    def test_non_origins_and_fake_or_mismatched_endpoints_are_rejected(self):
        for server in ["http://endlessnet.ru", "https://user:password@endlessnet.ru", "https://endlessnet.ru/path", "https://endlessnet.ru/?token=value", "https://endlessnet.ru/#fragment"]:
            with self.assertRaises(ValueError):
                self.configure(server=server)
        for endpoint in ["0.0.0.0:51820", "127.0.0.1:51820", "169.254.0.1:51820", "224.0.0.1:51820", "192.168.1.10:1234"]:
            with self.assertRaises(ValueError):
                self.configure(endpoint=endpoint)


if __name__ == "__main__":
    unittest.main()
