"""Unit fixtures границ publisher; настоящие GitHub releases не создаются."""

import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location("client_ui_ci", Path(__file__).resolve().parents[1] / "ci.py")
CI = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CI)
HEAD = "a" * 40
EVENT = {"GITHUB_EVENT_NAME": "push", "GITHUB_REF": "refs/tags/v0.1.0",
         "GITHUB_REPOSITORY": CI.REPOSITORY, "GITHUB_SHA": HEAD}
PROFILE = json.loads((Path(__file__).resolve().parents[2] / ".ci/profile.json").read_text())


class FakeGitHub:
    def __init__(self):
        self.release = None
        self.bytes = {}
        self.fail_upload = False
        self.cancel_upload = False
        self.created = 0
        self.promoted = 0

    def run(self, arguments, cwd, **_):
        if arguments[:3] == ["git", "rev-parse", "HEAD"]:
            return HEAD
        if arguments[:2] == ["gh", "api"]:
            endpoint = arguments[-1]
            if endpoint.endswith("/git/ref/tags/v0.1.0"):
                return json.dumps({"object": {"type": "commit", "sha": HEAD}})
            if endpoint.endswith("/releases"):
                return json.dumps([[self.release] if self.release else []])
        if arguments[:2] == ["gh", "release"]:
            action = arguments[2]
            if action == "view":
                return json.dumps({"tagName": self.release["tag_name"],
                                   "targetCommitish": self.release["target_commitish"],
                                   "isDraft": self.release["draft"],
                                   "isPrerelease": self.release["prerelease"],
                                   "assets": self.release["assets"]})
            if action == "create":
                self.created += 1
                self.release = {"tag_name": "v0.1.0", "target_commitish": HEAD,
                                "draft": True, "prerelease": False, "assets": []}
            elif action == "upload":
                if self.cancel_upload and self.bytes:
                    self.cancel_upload = False
                    raise KeyboardInterrupt()
                if self.fail_upload and self.bytes:
                    self.fail_upload = False
                    raise subprocess.CalledProcessError(1, arguments)
                path = Path(arguments[4])
                self.bytes[path.name] = path.read_bytes()
                self.release["assets"].append({"name": path.name})
            elif action == "download":
                directory = Path(arguments[arguments.index("--dir") + 1])
                for name, content in self.bytes.items():
                    (directory / name).write_bytes(content)
            elif action == "edit":
                self.promoted += 1
                self.release["draft"] = False
            else:
                raise AssertionError(arguments)
            return ""
        raise AssertionError(arguments)


class PipelineTests(unittest.TestCase):
    def setUp(self):
        # Сообщение fake publisher не должно выглядеть как настоящий GitHub release.
        printer = patch.object(CI, "print", create=True)
        printer.start()
        self.addCleanup(printer.stop)

    def test_sdk_cold_start_is_bootstrapped_before_machine_json(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / ".flutter-version").write_text(CI.FLUTTER_VERSION)
            machine = json.dumps({"frameworkVersion": CI.FLUTTER_VERSION,
                                  "frameworkRevision": CI.FLUTTER_REVISION,
                                  "dartSdkVersion": CI.DART_VERSION})
            with patch.object(CI, "run", side_effect=["Downloading Dart SDK...", machine]) as command:
                CI.verify_flutter(root)
            self.assertEqual(command.call_args_list[0].args[0], ["flutter", "--version"])
            self.assertEqual(command.call_args_list[1].args[0], ["flutter", "--version", "--machine"])

    def fixture(self, root):
        (root / ".ci").mkdir()
        (root / ".ci/profile.json").write_text(json.dumps(PROFILE))
        (root / "app").mkdir()
        (root / "app/pubspec.yaml").write_text("name: fixture\n")
        (root / "app/pubspec.lock").write_text("packages: {}\n")
        out = root / ".artifacts"
        out.mkdir()
        for artifact in PROFILE["artifacts"]:
            suffix = ".zip" if artifact["target"]["os"] == "windows" else ".tar.gz"
            path = out / (artifact["name"] + suffix)
            path.write_bytes(artifact["name"].encode())
            (out / (path.name + ".json")).write_text(json.dumps({
                "repository": CI.REPOSITORY, "commit": HEAD, "dirty": False,
                "target": f"{artifact['target']['os']}-{artifact['target']['arch']}",
                "archive": path.name, "sha256": CI.sha256(path)}))
        return out

    def test_only_exact_normal_v0_tag_push_is_allowed(self):
        self.assertEqual(CI.validate_event(EVENT, HEAD), "v0.1.0")
        for changes in ({"GITHUB_EVENT_NAME": "workflow_dispatch"},
                        {"GITHUB_REF": "refs/heads/main"},
                        {"GITHUB_REF": "refs/tags/v0.01.0"},
                        {"GITHUB_REF": "refs/tags/v0.1.0-rc.1"},
                        {"GITHUB_REF": "refs/tags/api/v0.1.0"},
                        {"GITHUB_SHA": "b" * 40}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                CI.validate_event({**EVENT, **changes}, HEAD)

    def test_profile_rejects_missing_target_or_package(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            self.assertEqual(CI.load_profile(root)["component"], "client-ui")
            profile = copy.deepcopy(PROFILE)
            profile["artifacts"].pop()
            (root / ".ci/profile.json").write_text(json.dumps(profile))
            with self.assertRaises(ValueError):
                CI.load_profile(root)
            (root / ".ci/profile.json").write_text(json.dumps(PROFILE))
            (root / "app/pubspec.lock").unlink()
            with self.assertRaises(ValueError):
                CI.load_profile(root)

    def test_archive_metadata_is_deterministic(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "bundle"
            source.mkdir()
            file = source / "application"
            file.write_bytes(b"binary fixture")
            for windows, suffix in ((False, ".tar.gz"), (True, ".zip")):
                first, second = root / ("first" + suffix), root / ("second" + suffix)
                CI.archive(source, first, windows=windows)
                os.utime(file, (1234567890, 1234567890))
                CI.archive(source, second, windows=windows)
                self.assertEqual(first.read_bytes(), second.read_bytes())

    def test_draft_retry_allows_only_missing_identical_assets(self):
        self.assertEqual(CI.reconcile_assets({"a": "1"}, {"a": "1", "b": "2"}, draft=True), ["b"])
        for existing, expected, draft in (({"a": "0"}, {"a": "1"}, True),
                                          ({"a": "1"}, {"a": "1", "b": "2"}, False),
                                          ({"extra": "1"}, {"a": "1"}, True)):
            with self.assertRaises(ValueError):
                CI.reconcile_assets(existing, expected, draft=draft)

    def test_annotated_tag_is_peeled_and_moved_tag_rejected(self):
        responses = [{"object": {"type": "tag", "sha": "c" * 40}},
                     {"object": {"type": "commit", "sha": HEAD}}]
        with patch.object(CI, "gh_json", side_effect=responses):
            CI.verify_remote_tag(Path.cwd(), "v0.1.0", HEAD)
        with patch.object(CI, "gh_json", return_value={"object": {"type": "commit", "sha": "d" * 40}}):
            with self.assertRaises(ValueError):
                CI.verify_remote_tag(Path.cwd(), "v0.1.0", HEAD)

    def test_publish_and_identical_retry_create_one_release(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            out = self.fixture(root)
            github = FakeGitHub()
            with patch.object(CI, "run", side_effect=github.run), patch.dict(os.environ, EVENT, clear=True):
                CI.publish(root, out)
                CI.publish(root, out)
            self.assertEqual(github.created, 1)
            self.assertEqual(github.promoted, 1)
            self.assertFalse(github.release["draft"])
            self.assertEqual(len(github.bytes), 6)

    def test_partial_upload_stays_draft_and_retry_resumes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            out = self.fixture(root)
            github = FakeGitHub()
            github.fail_upload = True
            with patch.object(CI, "run", side_effect=github.run), patch.dict(os.environ, EVENT, clear=True):
                with self.assertRaises(subprocess.CalledProcessError):
                    CI.publish(root, out)
                self.assertTrue(github.release["draft"])
                self.assertEqual(len(github.bytes), 1)
                self.assertEqual(github.promoted, 0)
                CI.publish(root, out)
            self.assertEqual(github.created, 1)
            self.assertFalse(github.release["draft"])

    def test_cancelled_upload_cannot_promote_draft(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            out = self.fixture(root)
            github = FakeGitHub()
            github.cancel_upload = True
            with patch.object(CI, "run", side_effect=github.run), patch.dict(os.environ, EVENT, clear=True):
                with self.assertRaises(KeyboardInterrupt):
                    CI.publish(root, out)
            self.assertTrue(github.release["draft"])
            self.assertEqual(github.promoted, 0)
            self.assertEqual(len(github.bytes), 1)

    def test_dirty_artifact_cannot_create_release(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            out = self.fixture(root)
            metadata = next(out.glob("*.json"))
            identity = json.loads(metadata.read_text())
            identity["dirty"] = True
            metadata.write_text(json.dumps(identity))
            github = FakeGitHub()
            with patch.object(CI, "run", side_effect=github.run), patch.dict(os.environ, EVENT, clear=True):
                with self.assertRaises(ValueError):
                    CI.publish(root, out)
            self.assertEqual(github.created, 0)

    def test_changed_published_bytes_fail_without_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            out = self.fixture(root)
            github = FakeGitHub()
            with patch.object(CI, "run", side_effect=github.run), patch.dict(os.environ, EVENT, clear=True):
                CI.publish(root, out)
                original = dict(github.bytes)
                name = next(name for name in original if name.endswith(".zip"))
                (out / name).write_bytes(b"conflicting bytes")
                metadata = out / (name + ".json")
                identity = json.loads(metadata.read_text())
                identity["sha256"] = CI.sha256(out / name)
                metadata.write_text(json.dumps(identity))
                with self.assertRaises(ValueError):
                    CI.publish(root, out)
                self.assertEqual(github.bytes, original)


if __name__ == "__main__":
    unittest.main()
