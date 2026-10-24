# @RELEASE_TITLE@

Preview download for **Apple silicon (M1 or later), macOS @MINIMUM_MACOS@ or later**. Xcode and an Apple developer account are not needed to run the app.

@CHANNEL_NOTE@

**This app is ad-hoc signed and is not notarized by Apple.** Its signature does not verify the developer's identity, and macOS may block the first launch. The release is provided under the MIT License; a copy is included in the download and app bundle.

## Install

1. Download `@ARCHIVE@` from this project's GitHub Releases page and unzip it.
2. Quit an existing Blink instance before replacing it. Move `Blink.app` into Applications (or `~/Applications`).
3. Open Blink. If macOS says Apple cannot verify the app, and you trust this download, open **System Settings → Privacy & Security** after the attempted launch, then choose **Open Anyway** and confirm **Open**. See [Apple's first-launch instructions](https://support.apple.com/en-us/102445). Managed Macs may restrict this option.
4. Complete setup, then find Blink's eye icon in the menu bar. Enable launch at login only after moving the app to its permanent location.

If macOS reports that the app is damaged or contains malware, do not use these instructions to bypass that warning. Download a fresh copy from the project release and report the problem.

## Verify the download

Download `@CHECKSUM@` from the same release into the same folder as the ZIP, then run:

```sh
shasum -a 256 -c @CHECKSUM@
```

The archive should report `OK`. This checks that it matches the release's checksum; it does not provide Apple notarization or independently establish who published it.

## Updates and verification limits

Updates are installed manually: quit Blink, replace the app in Applications, then reopen it. Settings and today's counters are stored separately from the app bundle.

The workflow that built this download runs default tests and verifies the packaged signature and checksum. Interactive desktop checks and a full normal-use working-day trial are separate acceptance checks; see the project's [verification status](https://github.com/larinam/blink/blob/@SOURCE_REF@/docs/verification.md). A passing package check does not mean Apple has scanned or approved this app.
