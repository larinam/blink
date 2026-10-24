#!/usr/bin/env python3
"""Publish only the rolling development tag from a verified main-push package."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

TAG = "development"
MARKER = re.compile(r"<!-- blink-development:([1-9][0-9]*):([1-9][0-9]*):([0-9a-f]{40}) -->")


def gh(*args, missing_ok=False):
    result = subprocess.run(["gh", *args], capture_output=True, text=True)
    if result.returncode:
        if missing_ok and "(HTTP 404)" in result.stderr:
            return None
        raise RuntimeError(result.stderr.strip() or "GitHub request failed")
    return result.stdout


def api(endpoint, method="GET", fields=None, missing_ok=False):
    args = ["api", "--method", method, endpoint]
    for key, value in (fields or {}).items():
        flag = "-F" if isinstance(value, (bool, int)) else "-f"
        args += [flag, f"{key}={str(value).lower() if isinstance(value, bool) else value}"]
    output = gh(*args, missing_ok=missing_ok)
    return json.loads(output) if output and output.strip() else None


def package(directory, sha, build_id):
    info = json.loads((directory / "build-info.json").read_text())
    if info.get("channel") != "development" or info.get("source_revision") != sha or info.get("build_id") != build_id:
        raise ValueError("Package channel, source revision or build ID does not match this workflow run")
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", info.get("version", "")):
        raise ValueError("Invalid package version")
    if not re.fullmatch(r"[0-9]+\." + re.escape(build_id), info.get("bundle_version", "")):
        raise ValueError("Bundle version does not contain this run and attempt")
    archive_name = f"Blink-{info['version']}-development.{info['bundle_version']}-{sha[:12]}-macos-arm64.zip"
    checksum_name = f"SHA256SUMS-development.{info['bundle_version']}-{sha[:12]}.txt"
    if info.get("archive") != archive_name or info.get("checksum") != checksum_name:
        raise ValueError("Unexpected Development asset names")
    archive = directory / archive_name
    checksum = directory / checksum_name
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    if checksum.read_text().strip() != f"{digest}  {archive_name}":
        raise ValueError("Development ZIP checksum does not match")
    with zipfile.ZipFile(archive) as zipped:
        entry = "Blink.app/Contents/Info.plist"
        if zipped.namelist().count(entry) != 1:
            raise ValueError("ZIP must contain exactly one app Info.plist")
        bundle = plistlib.loads(zipped.read(entry))
    expected = {"CFBundleShortVersionString": info["version"], "CFBundleVersion": info["bundle_version"],
                "BlinkChannel": "development", "BlinkSourceRevision": sha}
    if any(bundle.get(key) != value for key, value in expected.items()):
        raise ValueError("Packaged app identity does not match its manifest")
    return info, archive, checksum


def owned_asset(name):
    return bool(re.fullmatch(
        r"(?:Blink-[0-9.]+-development\.[0-9.]+-[0-9a-f]{12}-macos-arm64\.zip|"
        r"SHA256SUMS-development\.[0-9.]+-[0-9a-f]{12}\.txt|"
        r"build-info-development\.[0-9.]+-[0-9a-f]{12}\.json)", name))


def main():
    if len(sys.argv) != 2:
        raise ValueError("Usage: scripts/publish-development.py <package-directory>")
    if os.environ.get("GITHUB_EVENT_NAME") != "push" or os.environ.get("GITHUB_REF") != "refs/heads/main":
        raise ValueError("Development publication requires a push to main")
    if not os.environ.get("GH_TOKEN"):
        raise ValueError("An explicit publication token is required")
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    sha = os.environ.get("GITHUB_SHA", "")
    run = os.environ.get("GITHUB_RUN_NUMBER", "")
    attempt = os.environ.get("GITHUB_RUN_ATTEMPT", "")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo) or not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise ValueError("Invalid repository or source SHA")
    if not all(re.fullmatch(r"[1-9][0-9]*", value) for value in (run, attempt)):
        raise ValueError("Run number and attempt must be positive integers")
    # A retry of only the publication job reuses the package from its successful
    # build job. Its artifact/build ID belongs to that attempt, not the retry.
    build_id = os.environ.get("BLINK_BUILD_ID", f"{run}.{attempt}")
    if not re.fullmatch(re.escape(run) + r"\.[1-9][0-9]*", build_id):
        raise ValueError("Package build ID must belong to this workflow run")
    package_attempt = build_id.split(".")[1]
    if int(package_attempt) > int(attempt):
        raise ValueError("Package cannot come from a future attempt")
    directory = Path(sys.argv[1]).resolve()
    info, archive, checksum = package(directory, sha, build_id)
    endpoint = f"repos/{repo}"
    existing = api(f"{endpoint}/releases/tags/{TAG}", missing_ok=True)
    old_assets = []
    if existing:
        markers = MARKER.findall(existing.get("body") or "")
        if len(markers) != 1 or not existing.get("prerelease") or existing.get("immutable"):
            raise ValueError("Refusing to replace an unowned, non-prerelease or immutable Development release")
        old_run, old_attempt, old_sha = markers[0]
        current = (int(run), int(package_attempt))
        previous = (int(old_run), int(old_attempt))
        if current == previous and sha != old_sha:
            raise ValueError("The same build ID cannot identify two source revisions")
        if current < previous:
            print("A newer Development build is already published; skipping.")
            return
        ref = api(f"{endpoint}/git/ref/tags/{TAG}", missing_ok=bool(existing.get("draft")))
        if ref and ref.get("object", {}).get("type") != "commit":
            raise ValueError("Development must use its own lightweight tag")
        old_assets = existing.get("assets", [])
    elif api(f"{endpoint}/git/ref/tags/{TAG}", missing_ok=True):
        raise ValueError("Refusing to take over an existing development tag without an owned release")

    with tempfile.TemporaryDirectory(prefix="blink-development-") as temporary:
        staging = Path(temporary)
        manifest = staging / f"build-info-development.{info['bundle_version']}-{sha[:12]}.json"
        shutil.copyfile(directory / "build-info.json", manifest)
        notes = staging / "notes.md"
        notes.write_text(f"<!-- blink-development:{run}:{package_attempt}:{sha} -->\n\n"
                         + (directory / "release-notes.md").read_text())
        assets = [str(archive), str(checksum), str(manifest)]
        title = f"Development — {info['version']} build {info['bundle_version']} ({sha[:7]})"
        if not existing:
            gh("release", "create", TAG, *assets, "--repo", repo, "--target", sha,
               "--draft", "--prerelease", "--latest=false", "--title", title, "--notes-file", str(notes))
        else:
            # Unique asset names preserve the previous ZIP/checksum pair if an
            # upload fails. Never hide an existing download while replacing it.
            gh("release", "upload", TAG, *assets, "--repo", repo, "--clobber")
        gh("release", "edit", TAG, "--repo", repo, "--draft=false", "--prerelease", "--latest=false",
           "--target", sha, "--title", title, "--notes-file", str(notes))
        # Advance the tag only after the new body and downloads are visible.
        # A failed tag update leaves the old diff base, so a later docs push can
        # detect and retry the still-unrecorded code change.
        ref = api(f"{endpoint}/git/ref/tags/{TAG}")
        if not ref or ref.get("object", {}).get("type") != "commit":
            raise ValueError("Development must use its own lightweight tag")
        if ref["object"]["sha"] != sha:
            api(f"{endpoint}/git/refs/tags/{TAG}", "PATCH", {"sha": sha, "force": True})
        keep = {Path(asset).name for asset in assets}
        for asset in old_assets:
            if asset["name"] not in keep and owned_asset(asset["name"]):
                api(f"{endpoint}/releases/assets/{int(asset['id'])}", "DELETE")
    print(f"Published Development build {info['bundle_version']} from {sha}.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, KeyError, zipfile.BadZipFile) as error:
        print(f"publish-development: {error}", file=sys.stderr)
        sys.exit(1)
