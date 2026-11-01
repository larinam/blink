# Security policy

## Reporting a vulnerability

Please report security issues privately, not in public issues or pull requests. Use GitHub's [private vulnerability reporting](https://github.com/larinam/blink/security/advisories/new) (**Security → Report a vulnerability**), or email **larinam@gmail.com** if you cannot use GitHub. Include the affected version or commit, steps to reproduce, and the impact you observed. You will get a reply once the report has been reviewed. Please keep the details private until a fix is available.

## Supported versions

Blink is maintained on a best-effort basis. Fixes go into `main`, the next Development build, and the next numbered release; earlier releases do not receive backports. Release downloads are previews, as described in [release downloads](docs/releases.md).

## Scope

Blink runs locally and offline. It makes no network requests of its own. Two reference links open in your browser only when clicked. The Feedback page opens an email app or Gmail in your browser only when you choose that option, with no attachments or automatic sending. Blink does not use the camera, microphone, screen recording, or input event taps. Relevant reports include:

- reading or changing saved state in `~/Library/Application Support/Blink/` in a way the app does not intend;
- the global shortcut or system activity checks observing more than the [documented behavior](README.md#privacy-and-storage);
- the release ZIP, checksum, packaging scripts, or [release workflow](.github/workflows/release.yml).

Release downloads are ad-hoc signed and not notarized by Apple, so macOS asks you to approve the app on first launch. That is documented behavior, not a vulnerability. A damaged-app or malware warning is different: please report it together with the download details.
