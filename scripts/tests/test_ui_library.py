"""Unit fixtures не запускают Flutter; доказывают разделение entrypoints."""
import importlib.util
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
SPEC = importlib.util.spec_from_file_location("ui_library_checks", ROOT / "scripts/check_ui_library.py")
LIBRARY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(LIBRARY)


class LibraryChecksTests(unittest.TestCase):
    def test_default_checks_do_not_execute_design_suite(self):
        with patch.object(LIBRARY, "verify_flutter"), patch.object(LIBRARY, "run") as run:
            LIBRARY.check(ROOT)
        test_calls = [call.args[0] for call in run.call_args_list if call.args[0][:2] == ["flutter", "test"]]
        self.assertEqual(len(test_calls), 1)
        self.assertTrue(all(entry.startswith("test/") for entry in test_calls[0][3:]))

    def test_explicit_design_does_not_execute_ordinary_suite(self):
        with patch.object(LIBRARY, "verify_flutter"), patch.object(LIBRARY, "run") as run:
            LIBRARY.check(ROOT, design=True)
        test_calls = [call.args[0] for call in run.call_args_list if call.args[0][:2] == ["flutter", "test"]]
        self.assertEqual(test_calls, [["flutter", "test", "--no-pub", "test_design/components"]])
