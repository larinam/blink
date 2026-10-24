# Development and verification commands

Run commands from the repository root. The package requires Swift tools 6.4 or newer (Xcode 27) and macOS 26. Bare `swift test` uses the active developer directory, so select Xcode with `sudo xcode-select -s /Applications/Xcode.app`; the scripts under `scripts/` source `scripts/toolchain.sh`, which falls back to `/Applications/Xcode.app` when only the Command Line Tools are selected. There are no third-party dependencies. Open `Package.swift` in Xcode for source development.

## Build and isolated use

```sh
scripts/build.sh           # release, arm64, ad-hoc signed build/Blink.app
scripts/build.sh debug     # debug bundle at the same path
open build/Blink.app
```

The script generates the icon, includes the MIT license, and verifies the bundle signature. Both configurations overwrite the same bundle. Before replacing a build under a live observation, finish or explicitly stop that recording and preserve its results; binary changes invalidate the trial. Set `BLINK_BUILD_DIR` to a different output directory when a separate app bundle is needed; SwiftPM compilation still uses `.build/`.

For Development and numbered ZIP packages, checksums, and GitHub releases, see [release downloads](releases.md). `scripts/package-release.sh` builds into a fresh temporary directory and leaves the normal `build/Blink.app` untouched.

Bundle metadata lives in `Packaging/Info.plist`; the icon generator is `Tools/make-icon.swift`. Keep generated icons and bundles in `build/`. To verify packaging while Blink is running from that directory, copy the source tree to a temporary directory (excluding `.build/`, `build/`, and `qa-output/`) and run the build there.

Use the bundle for normal use and launch at login. Copy it to a stable location such as `~/Applications` before enabling login launch. Launch-at-login status belongs to macOS and is shown in Settings.

For a separate development state directory, launch the executable with a process-local override:

```sh
BLINK_STATE_DIR="$(mktemp -d /tmp/blink-state.XXXXXX)" \
  ./build/Blink.app/Contents/MacOS/Blink
```

Each state directory has an exclusive process lease. A second process using the same directory exits before loading or writing state; a fresh `BLINK_STATE_DIR` allows a separate development process. That process still creates windows and tries to register the same global shortcut, which may be unavailable while another Blink is running. Quit the installed copy when testing that shortcut. The override does not redirect another running instance.

Older builds without the lease do not coordinate with it. Quit them before testing against the normal state directory; use a fresh isolated directory when keeping an older installed build running.

## Default tests

```sh
swift test
```

Core tests cover deterministic schedules, collisions, actions, quiet/grace, absences, settings, persistence, invalid decoded state, coarse ticks, and simulated working days. App adapter tests cover availability partitioning, unlock reconciliation, settings conversion, and storage behavior. Default execution skips opt-in native animation, pointer, rendering, and overlay checks. A green default run is not evidence that those checks ran.

App regressions also cover state-directory contention/release/aliases, editor draft baselines, announcement suppression/deduplication, and native U.S./Dvorak key translation without selecting another input source. `BLINK_HIT_CHECKS=1` includes a Settings window lifecycle check: edit a real text field, change pages, and close/reopen the test-owned window without losing unsaved text.

The selected state directory must support advisory locking; startup fails closed if ownership cannot be established. Use an isolated directory on a local filesystem if a development override points to a filesystem without locking support.

## Continuous integration

The [CI workflow](../.github/workflows/ci.yml) runs on pull requests targeting `main` and pushes to `main`, using the same Apple silicon `xcode-27` runner as release packaging. The **Test and build** job checks the release automation scripts, runs the default `swift test` suite, then `scripts/build.sh release`, which assembles and verifies the ad-hoc-signed app bundle. Checkout uses GitHub's default PR merge revision, so the check tests the proposed merge with the target branch. A new pull-request run cancels the older run for that pull request; `main` runs are serialized instead, so a publication is never cancelled midway.

On a `main` push that changes app-affecting paths since the `development` tag, **Test and build** packages a Development download instead of the plain bundle, and the separate **Publish Development download** job updates the rolling `development` pre-release. Only that job has `contents: write`; **Test and build** has `contents: read`, does not retain checkout credentials, and needs no repository secrets. Pull requests and documentation-only pushes publish nothing, and CI never installs or launches the app. Native desktop tests remain separate opt-in checks. Repository rules can require **Test and build** before merging; those rules are configured separately from the workflow.

Follow [AGENTS.md](../AGENTS.md) when verifying workflow changes: use both `actionlint` and `act`. On a Mac with Xcode, run the CI job natively with `act pull_request -W .github/workflows/ci.yml -j test-and-build -P xcode-27=-self-hosted`, using an isolated workspace and no CI secrets. Host mode is not container-isolated. Do not rely on `-n` to prevent execution: act can run native shell steps despite that flag. Keep publishing out of local CI verification: the `pull_request` event and `-j test-and-build` never select the publish job or the release workflow. Local host execution does not establish GitHub-hosted runner or merge-checkout behavior.

## Native UI checks

Run these separately, with an unlocked session and awake displays. They exercise test-owned native windows and can briefly show overlays. Choose fresh output directories to preserve earlier evidence.

```sh
BLINK_HIT_CHECKS=1 BLINK_ANIMATION_CHECKS=1 \
  BLINK_RENDER_DIR="$PWD/qa-output/ui-renders" \
  BLINK_ANIMATION_RENDER_DIR="$PWD/qa-output/blink-frames" \
  swift test

BLINK_NATIVE_CHECKS=1 swift test --filter OverlayLifecycleTests
```

Inspect light/dark renders as well as test output. Pointer checks verify actual padded-edge activation and gaps, native keyboard dispatch, sidebar selection, and help targets; guide links are intercepted rather than opened in a browser. Target bounds are read from SwiftUI's private `_FocusRingView` layout on macOS 26, so a failure there can be a SwiftUI representation change rather than a smaller target. Animation checks verify the finite eye sequence, live Reduce Motion input, bounded cleanup, and a subsequent cue. Overlay checks cover connected-display placement/recreation, focus, preview teardown, and the native fade probe. They do not simulate physical cable changes or establish subjective smoothness.

To run the fade probe in `Tools/BlinkAnimationCheck.swift` directly after a debug build/test has produced `BlinkCore`:

```sh
mkdir -p qa-output
scripts/check-blink-animation.sh > qa-output/blink-native-animation-new.json
```

The script builds actual presentation sources into a temporary AppKit executable with its own event loop; it does not reload Blink or write the user's saved state. It records session/display prerequisites at checkpoints, intermediate opacity progression, focus, geometry, cancellation/replacement, and cleanup path. The `BLINK_ANIMATION_PROBE` trace hooks are absent from normal builds.

A locked/asleep prerequisite rejection is not a visible-animation pass. A fallback-only cleanup is not an ordinary-completion pass. Under load, the bounded fallback can win the race safely; preserve the result and repeat on an otherwise idle Mac. Do not lengthen the fallback deadline just to satisfy the probe. See [interface behavior](interface.md#blink-cue).

## Normal-use working-day recording

These instructions are for the full working-day acceptance trial described in [verification](verification.md). First verify the intended Blink PID, executable path, and saved-state path, and choose a new output directory. Replace `12345` with that verified PID:

```sh
python3 scripts/soak.py \
  --pid 12345 \
  --binary "$PWD/build/Blink.app/Contents/MacOS/Blink" \
  --state "$HOME/Library/Application Support/Blink/state.json" \
  --hours 8 \
  --output "$PWD/qa-output/working-day-new"
```

Use the installed executable path if observing an installed bundle. The recorder checks PID start time and binary hash, samples CPU/RSS and state size/save age about once a minute, and writes `status.json` and `samples.jsonl`. The script opens its log for writing, so an existing output directory would overwrite evidence. It does not synthesize input or defeat idle/quiet/sleep behavior.

Its elapsed clock (`time.monotonic`) can exclude system suspension; inspect elapsed time and wall-clock gaps separately. `measurement_complete` still requires review of resource trends, sleep gaps, naturally scheduled reminders, controls, and final native responsiveness. An interrupted run remains partial evidence. Report the build identity, results and limits with the evidence, for example in the pull request or release notes; a result applies only to the build it observed.
