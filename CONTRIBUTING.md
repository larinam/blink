# Contributing to Blink

Thanks for your interest. Blink is a small, offline macOS menu bar app with deliberate scope boundaries, so please open an issue to discuss a feature or behavior change before writing it. Bug reports, focused fixes, and documentation corrections are welcome directly.

Report security issues privately as described in [SECURITY.md](SECURITY.md), not in public issues.

## Scope

Check [requirements](docs/requirements.md#explicit-boundaries) and [decisions](docs/decisions.md) before proposing a change. Camera tracking, strict enforcement, cloud sync, and similar features are deliberately deferred. A change that alters a settled decision should explain why the original reasoning no longer holds.

The project has no third-party dependencies. Discuss any new dependency in an issue first.

## Set up

You need an Apple silicon Mac running macOS 26 or later, with Xcode 27 or newer selected as the active developer directory:

```sh
sudo xcode-select -s /Applications/Xcode.app
```

The Command Line Tools alone cannot build the app because the SwiftUI macro plugins ship only inside Xcode. The scripts under `scripts/` fall back to `/Applications/Xcode.app` when only the Command Line Tools are selected; bare `swift test` does not.

```sh
swift test                 # default tests
scripts/build.sh debug     # debug app bundle at build/Blink.app
```

Use an isolated state directory while developing so your own settings and counters stay untouched:

```sh
BLINK_STATE_DIR="$(mktemp -d /tmp/blink-state.XXXXXX)" \
  ./build/Blink.app/Contents/MacOS/Blink
```

It still registers the global shortcut, so quit any installed Blink first. See [development](docs/development.md#build-and-isolated-use) for details.

## Test your change

- Run `swift test` and make sure it passes. Add or update tests for scheduling changes in `Tests/BlinkCoreTests` and for adapter or storage changes in `Tests/BlinkAppTests`.
- Default runs skip the native UI checks (pointer targets, rendering, blink animation, overlays). If you change interface or overlay code, run the relevant [native UI checks](docs/development.md#native-ui-checks) on an unlocked, awake Mac and say which ones you ran. A green default run does not show that they passed.
- Keep scheduling logic in `BlinkCore`, which stays Foundation-only and independent of the interface. See [architecture](docs/architecture.md).

The [CI workflow](.github/workflows/ci.yml) runs default tests and builds the ad-hoc-signed release bundle for pull requests targeting `main` and pushes to `main`. Its check is named **Test and build**. Pull requests never publish; app changes merged to `main` update the rolling Development download. CI skips the opt-in desktop checks; include the relevant local results when changing UI code.

## Pull requests

- Keep each pull request focused on one change and describe what changed, why, and how you tested it.
- Update the relevant guide when behavior changes: [requirements](docs/requirements.md), [architecture](docs/architecture.md), [decisions](docs/decisions.md), or [verification](docs/verification.md). Keep docs current and concise; use Git history for superseded proposals and review discussions.
- Don't bump the version or create release tags; releases follow [release downloads](docs/releases.md).

## License

Blink is available under the [MIT License](LICENSE). By submitting a contribution, you agree that it is licensed under the same terms.
