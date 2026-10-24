#!/usr/bin/env python3
"""Offline regression checks for release gating and the rolling publisher."""
import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("publisher", ROOT / "scripts/publish-development.py")
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)
SHA = "a" * 40
OTHER_SHA = "b" * 40


class Changes(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="blink-change-test-")
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "release-test@example.invalid")
        self.git("config", "user.name", "Release fixture")
        self.git("config", "core.hooksPath", "/dev/null")
        self.git("config", "commit.gpgSign", "false")
        (self.repo / "scripts").mkdir()
        shutil.copyfile(ROOT / "scripts/development-changes.sh", self.repo / "scripts/development-changes.sh")
        self.write("Sources/App.swift", "initial")
        self.write("README.md", "initial")
        self.base = self.commit()

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.repo), *args], text=True).strip()

    def write(self, name, content):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def commit(self):
        self.git("add", "--all")
        self.git("commit", "-qm", "fixture")
        return self.git("rev-parse", "HEAD")

    def changed(self, before=None):
        return subprocess.check_output(["bash", str(self.repo / "scripts/development-changes.sh"),
                                        before or self.base], text=True).strip()

    def test_docs_only(self):
        self.write("docs/new.md", "documentation")
        self.commit()
        self.assertEqual(self.changed(), "false")

    def test_code_then_docs_uses_last_download(self):
        self.git("tag", "development", self.base)
        self.write("Sources/App.swift", "new code")
        code = self.commit()
        self.write("README.md", "later docs")
        self.commit()
        self.assertEqual(self.changed(code), "true")

    def test_docs_after_current_download(self):
        self.git("tag", "development", self.base)
        self.write("README.md", "later docs")
        self.commit()
        self.assertEqual(self.changed(), "false")

    def test_deleted_or_renamed_code(self):
        (self.repo / "Sources/App.swift").rename(self.repo / "moved.md")
        self.commit()
        self.assertEqual(self.changed(), "true")

    def test_packaging_and_license_affect_download(self):
        for name in ["Packaging/INSTALL.md", "LICENSE", ".github/workflows/ci.yml", "Package.swift"]:
            with self.subTest(path=name):
                self.git("reset", "--hard", self.base)
                self.write(name, "changed")
                self.commit()
                self.assertEqual(self.changed(), "true")

    def test_missing_before_builds_conservatively(self):
        self.assertEqual(self.changed("0" * 40), "true")
        self.assertEqual(self.changed("f" * 40), "true")

    def test_rewritten_main_is_changed(self):
        self.write("Sources/App.swift", "development")
        self.commit()
        self.git("tag", "development")
        self.git("reset", "--hard", self.base)
        self.write("README.md", "rewritten branch")
        self.commit()
        self.assertEqual(self.changed(), "true")

    def test_git_error_is_not_a_docs_only_result(self):
        binary = self.repo / "fake-bin"
        binary.mkdir()
        fake_git = binary / "git"
        fake_git.write_text('#!/bin/sh\ncase "$1" in\nrev-parse) printf "%s\\n" ' + self.base
                            + ';;\nmerge-base) exit 128;;\nesac\n')
        fake_git.chmod(0o755)
        result = subprocess.run(["bash", str(self.repo / "scripts/development-changes.sh"), self.base],
                                env={**os.environ, "PATH": f"{binary}:{os.environ['PATH']}"}, capture_output=True, text=True)
        self.assertEqual(result.returncode, 128)
        self.assertEqual(result.stdout, "")


def make_package(directory, run=12, attempt=1, sha=SHA):
    directory.mkdir(parents=True)
    version = f"3.{run}.{attempt}"
    archive = f"Blink-1.1.1-development.{version}-{sha[:12]}-macos-arm64.zip"
    checksum = f"SHA256SUMS-development.{version}-{sha[:12]}.txt"
    info = {"channel": "development", "version": "1.1.1", "bundle_version": version,
            "build_id": f"{run}.{attempt}", "source_revision": sha, "archive": archive, "checksum": checksum}
    plist = {"CFBundleShortVersionString": "1.1.1", "CFBundleVersion": version,
             "BlinkChannel": "development", "BlinkSourceRevision": sha}
    with zipfile.ZipFile(directory / archive, "w") as zipped:
        zipped.writestr("Blink.app/Contents/Info.plist", plistlib.dumps(plist))
    digest = hashlib.sha256((directory / archive).read_bytes()).hexdigest()
    (directory / checksum).write_text(f"{digest}  {archive}\n")
    (directory / "build-info.json").write_text(json.dumps(info))
    (directory / "release-notes.md").write_text(f"Development from {sha}.\n")
    return info


class GitHubFixture:
    """A local in-memory gh transport; never invokes the installed gh command."""
    def __init__(self, old=None, fail=None):
        self.release = None
        self.ref = None
        self.files = {}
        self.calls = []
        self.fail = fail
        if old:
            self.release = {"body": f"<!-- blink-development:{old[0]}:{old[1]}:{OTHER_SHA} -->\nold notes",
                            "prerelease": True, "draft": False, "immutable": False, "assets": []}
            self.ref = {"object": {"type": "commit", "sha": OTHER_SHA}}
            old_version = f"3.{old[0]}.{old[1]}"
            for name in [f"Blink-1.1.1-development.{old_version}-bbbbbbbbbbbb-macos-arm64.zip",
                         f"SHA256SUMS-development.{old_version}-bbbbbbbbbbbb.txt",
                         f"build-info-development.{old_version}-bbbbbbbbbbbb.json", "user-attachment.txt"]:
                self.add(name, b"previous download")

    def add(self, name, data):
        self.files[name] = data
        self.release["assets"] = [a for a in self.release["assets"] if a["name"] != name]
        self.release["assets"].append({"name": name, "id": len(self.calls) * 100 + len(self.files)})

    def __call__(self, *args, missing_ok=False):
        self.calls.append(args)
        if args[0] == "api":
            method, endpoint = args[2:4]
            if method == "GET":
                value = self.release if "/releases/tags/" in endpoint else self.ref
                if value is None and not missing_ok:
                    raise RuntimeError("missing fixture value")
                return json.dumps(value) if value is not None else None
            if method == "PATCH":
                if self.fail == "tag": raise RuntimeError("injected tag failure")
                assert endpoint.endswith("/git/refs/tags/development")
                sha = next(a[4:] for a in args if a.startswith("sha="))
                self.ref = {"object": {"type": "commit", "sha": sha}}
                return ""
            assert method == "DELETE" and "/releases/assets/" in endpoint
            asset = next(a for a in self.release["assets"] if a["id"] == int(endpoint.rsplit("/", 1)[1]))
            self.files.pop(asset["name"])
            self.release["assets"].remove(asset)
            return ""
        assert args[:1] == ("release",) and args[2] == "development"
        operation = args[1]
        if operation == self.fail: raise RuntimeError(f"injected {operation} failure")
        if operation in ["create", "upload"]:
            if operation == "create":
                assert "--draft" in args and "--prerelease" in args and "--latest=false" in args
                self.release = {"body": Path(args[args.index("--notes-file") + 1]).read_text(),
                                "prerelease": True, "draft": True, "immutable": False, "assets": []}
                self.ref = {"object": {"type": "commit", "sha": args[args.index("--target") + 1]}}
            for name in args[3:args.index("--repo")]:
                path = Path(name)
                self.add(path.name, path.read_bytes())
        else:
            assert operation == "edit" and "--draft=false" in args and "--latest=false" in args
            self.release["body"] = Path(args[args.index("--notes-file") + 1]).read_text()
            self.release["draft"] = False
        return ""

    def writes(self):
        return [c for c in self.calls if c[0] != "api" or c[2] != "GET"]


class Publication(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="blink-publisher-test-")
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name) / "package"
        self.info = make_package(self.directory)

    def publish(self, service, **env):
        context = {"GITHUB_EVENT_NAME": "push", "GITHUB_REF": "refs/heads/main", "GITHUB_REPOSITORY": "fixture/blink",
                   "GITHUB_SHA": SHA, "GITHUB_RUN_NUMBER": "12", "GITHUB_RUN_ATTEMPT": "1", "GH_TOKEN": "offline-fixture"}
        context.update(env)
        with patch.dict(os.environ, context, clear=True), patch.object(sys, "argv", ["publisher", str(self.directory)]), \
                patch.object(publisher, "gh", service), contextlib.redirect_stdout(io.StringIO()):
            publisher.main()

    def test_first_publication_stages_then_publishes(self):
        service = GitHubFixture()
        self.publish(service)
        self.assertFalse(service.release["draft"])
        self.assertEqual(service.ref["object"]["sha"], SHA)
        self.assertEqual(len(service.files), 3)

    def test_update_preserves_unrelated_attachment_and_cleans_old_build(self):
        service = GitHubFixture(old=(11, 1))
        self.publish(service)
        self.assertEqual(len(service.files), 4)
        self.assertIn("user-attachment.txt", service.files)
        edit = next(i for i, c in enumerate(service.calls) if c[:2] == ("release", "edit"))
        self.assertTrue(all(i > edit for i, c in enumerate(service.calls) if c[:3] == ("api", "--method", "DELETE")))

    def test_old_rerun_cannot_roll_download_back(self):
        service = GitHubFixture(old=(13, 1))
        shutil.rmtree(self.directory)
        make_package(self.directory, attempt=99)
        self.publish(service, GITHUB_RUN_ATTEMPT="99")
        self.assertEqual(service.writes(), [])

    def test_new_attempt_of_same_run_can_publish(self):
        service = GitHubFixture(old=(12, 1))
        service.release["body"] = service.release["body"].replace(OTHER_SHA, SHA)
        shutil.rmtree(self.directory)
        make_package(self.directory, attempt=2)
        self.publish(service, GITHUB_RUN_ATTEMPT="2")
        self.assertIn(f"blink-development:12:2:{SHA}", service.release["body"])

    def test_foreign_or_immutable_release_is_untouched(self):
        for field, value in [("body", "not ours"), ("immutable", True), ("prerelease", False)]:
            with self.subTest(field=field):
                service = GitHubFixture(old=(11, 1))
                service.release[field] = value
                with self.assertRaises(ValueError): self.publish(service)
                self.assertEqual(service.writes(), [])

    def test_wrong_context_or_missing_token_never_calls_github(self):
        for env in [{"GITHUB_EVENT_NAME": "pull_request"}, {"GITHUB_REF": "refs/heads/other"}, {"GH_TOKEN": ""}]:
            with self.subTest(env=env):
                service = GitHubFixture()
                with self.assertRaises(ValueError): self.publish(service, **env)
                self.assertEqual(service.calls, [])

    def test_checksum_failure_never_calls_github(self):
        (self.directory / self.info["checksum"]).write_text("incorrect")
        service = GitHubFixture()
        with self.assertRaises(ValueError): self.publish(service)
        self.assertEqual(service.calls, [])

    def test_matching_checksum_does_not_accept_wrong_app_identity(self):
        archive = self.directory / self.info["archive"]
        with zipfile.ZipFile(archive) as zipped:
            bundle = plistlib.loads(zipped.read("Blink.app/Contents/Info.plist"))
        bundle["BlinkSourceRevision"] = OTHER_SHA
        with zipfile.ZipFile(archive, "w") as zipped:
            zipped.writestr("Blink.app/Contents/Info.plist", plistlib.dumps(bundle))
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        (self.directory / self.info["checksum"]).write_text(f"{digest}  {archive.name}\n")
        service = GitHubFixture()
        with self.assertRaises(ValueError): self.publish(service)
        self.assertEqual(service.calls, [])

    def test_build_id_cannot_be_reused_for_another_commit(self):
        service = GitHubFixture(old=(12, 1))
        with self.assertRaises(ValueError): self.publish(service)
        self.assertEqual(service.writes(), [])

    def test_initial_draft_can_be_recovered(self):
        service = GitHubFixture(old=(12, 1))
        service.release["body"] = service.release["body"].replace(OTHER_SHA, SHA)
        service.release["draft"] = True
        self.publish(service)
        self.assertFalse(service.release["draft"])
        self.assertEqual(service.ref["object"]["sha"], SHA)

    def test_retry_publication_uses_original_build_attempt(self):
        service = GitHubFixture(old=(12, 1))
        service.release["body"] = service.release["body"].replace(OTHER_SHA, SHA)
        self.publish(service, GITHUB_RUN_ATTEMPT="2", BLINK_BUILD_ID="12.1")
        self.assertIn(f"blink-development:12:1:{SHA}", service.release["body"])
        self.assertEqual(service.ref["object"]["sha"], SHA)

    def test_upload_or_edit_failure_preserves_previous_download_pair(self):
        for failure in ["upload", "tag", "edit"]:
            with self.subTest(failure=failure):
                service = GitHubFixture(old=(11, 1), fail=failure)
                previous = service.files.copy()
                with self.assertRaises(RuntimeError): self.publish(service)
                self.assertFalse(service.release["draft"])
                self.assertTrue(all(service.files.get(name) == data for name, data in previous.items()))
                self.assertFalse(any(c[:3] == ("api", "--method", "DELETE") for c in service.calls))

    def test_orphan_tag_is_not_taken_over(self):
        service = GitHubFixture()
        service.ref = {"object": {"type": "commit", "sha": OTHER_SHA}}
        with self.assertRaises(ValueError): self.publish(service)
        self.assertEqual(service.writes(), [])

    def test_permission_errors_are_not_treated_as_missing_release(self):
        result = subprocess.CompletedProcess([], 1, stdout="", stderr="GitHub: Forbidden (HTTP 403)")
        with patch.object(publisher.subprocess, "run", return_value=result):
            with self.assertRaises(RuntimeError): publisher.gh("api", "fixture", missing_ok=True)


if __name__ == "__main__":
    unittest.main()
