# GitHub release downloads

Blink's distribution path uses an ad-hoc signature and no Apple notarization. It needs no Apple Developer Program membership or signing credentials. Every download is a preview ZIP for Apple silicon and macOS 26 or later, with a SHA-256 checksum and first-launch instructions. Developer ID signing and notarization can be added later.

There are two channels:

| Channel | Produced by | GitHub release |
| --- | --- | --- |
| Development | A push to `main` that changes the app, its tests, packaging, tools, scripts or workflows | One rolling pre-release on the `development` tag, replaced by each new Development build and never marked Latest |
| Numbered | A pushed `v<version>` tag | A fixed release for that version, marked Latest; its assets are never replaced |

Documentation-only pushes run the tests but publish nothing. The checks are in the [CI workflow](../.github/workflows/ci.yml) and the [release workflow](../.github/workflows/release.yml).

## Development downloads

After **Test and build** passes on a `main` push, the workflow compares the commit with the current `development` tag. If app-affecting paths changed, it packages a Development build, and a separate job with write access publishes it. The comparison uses the last published Development build rather than only the previous push, so code from a superseded run is not skipped.

Each Development build records its full source commit and channel in the app bundle and manifest. Its bundle version is `<build>.<run>.<attempt>`: the build number from `Packaging/Info.plist`, followed by the workflow run number and attempt. **About Blink** shows the bundle version, `Development`, and the short commit.

Published asset names include the bundle version and the first 12 characters of the source commit:

```text
Blink-<version>-development.<bundle-version>-<short-sha>-macos-arm64.zip
SHA256SUMS-development.<bundle-version>-<short-sha>.txt
build-info-development.<bundle-version>-<short-sha>.json
```

New assets are uploaded before the previous ones are removed, so the release retains a complete ZIP and matching checksum during an update. A rerun of an older workflow run never replaces a newer Development build.

## Numbered releases

Before tagging, set `CFBundleShortVersionString` and `CFBundleVersion` in `Packaging/Info.plist` for the release, then commit and push. Choose an unused version; existing tags cannot be reused. The tag must exactly match the app version with a leading `v`:

```sh
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Packaging/Info.plist)"
git tag -a "v$version" -m "Blink $version preview"
git push origin "v$version"
```

The workflow runs default tests, packages and verifies the ZIP, and publishes the release immediately with the ZIP, `SHA256SUMS.txt` and `build-info.json`. It uses GitHub's Apple silicon [`xcode-27` runner](https://docs.github.com/en/actions/reference/runners/github-hosted-runners). Only the release job has `contents: write`; no Apple account, signing certificate or extra repository secret is used.

You can also run **Actions → Release → Run workflow** with an existing tag. The workflow checks out that tag and requires it to exist on GitHub; it never creates a tag from a moving branch. If a release for that tag already exists, creation fails without replacing it.

Because a numbered release is published as soon as the workflow finishes, check the recipient experience on the Development download of the same commit before tagging. A private repository's releases are visible only to people with repository access.

## Build a package locally

Packaging requires a clean working tree (ignored build output aside), because the bundle and installation notes record the checked-out commit. Run the [default tests](development.md#default-tests), then package the app:

```sh
swift test
scripts/package-release.sh                                         # numbered
scripts/package-release.sh --development 12.1 "$(git rev-parse HEAD)" # local Development example
```

CI supplies its own run number and attempt; `12.1` above is an illustrative local build ID. A numbered package writes:

```text
build/releases/v<version>/
  Blink-<version>-build.<build>-macos-arm64.zip
  SHA256SUMS.txt
  release-notes.md
  build-info.json
```

A Development package writes to `build/releases/development/`, using the unique ZIP and checksum names shown above; its local manifest remains `build-info.json`. An optional expected-version argument in numbered mode rejects a mismatch with `Packaging/Info.plist` before building.

The ZIP contains `Blink.app`, `INSTALL.md`, and `LICENSE`. Installation text and release notes are rendered from [Packaging/INSTALL.md](../Packaging/INSTALL.md); the manifest records the channel, version, bundle version, source commit, and asset names. The app bundle also carries the MIT license.

Packaging builds a fresh bundle in a temporary directory under `build/`, leaving `build/Blink.app` and the installed app untouched. It checks arm64 architecture and the ad-hoc signature, extracts the ZIP, verifies the extracted signature, executable permissions, executable bytes, build identity, license and instructions, then checks the archive checksum. It does not launch the app or access saved settings. The script refuses to overwrite an existing output directory; move a local package aside before packaging again.

## Check the recipient experience

Download the ZIP and checksum through a browser. Verify the checksum, unzip it, and follow `INSTALL.md` on a suitable Mac, preferably a separate Mac or test account. Confirm the expected first-launch warning, the per-app Open Anyway path where permitted, onboarding, menu controls, About identity, Quit, and a normal relaunch. Do not disable Gatekeeper globally or remove quarantine attributes to count this as a recipient-installation check.

Do not treat a damaged-app or malware warning as the ordinary unidentified-developer warning. Preserve the download and error details for investigation instead of bypassing them. Apple describes the different warnings and the per-app exception in its [first-launch guidance](https://support.apple.com/en-us/102445).

Record the version/build, source commit, and exact downloaded checksum with the [verification evidence](verification.md#report-a-verification-run). Local ZIP round-trip checks are packaging evidence; they do not establish browser-download behavior, native UI acceptance, or the full working-day trial. Default tests also skip opt-in desktop checks.
