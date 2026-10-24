# Important decisions

D1–D13 record settled choices in the current source and the reasons to preserve them. They do not state which build is installed or accepted; see [verification](verification.md).

## D1 — Keep scheduling deterministic

Foundation-only `BlinkCore` owns scheduling and counters; the macOS adapter supplies observations and owns windows, storage, sound, and login integration. Persistent presentation derives from the snapshot, so lost or repeated transient effects cannot desynchronize a countdown. This boundary makes collisions, coarse ticks, and simulated working days reproducible. See [architecture](architecture.md).

## D2 — Distinguish elapsed, wall, and counted time

Durations use continuous elapsed time; local midnight and quiet expiry use wall time; reminder schedules use counted screen time. The adapter differences continuous and suspending clocks to identify sleep without treating a busy main thread as rest. Closed-app time earns no credit. This preserves countdowns and schedules across clock changes, sleep, and relaunch. See [AvailabilityClock.swift](../Sources/Blink/Platform/AvailabilityClock.swift) and [ReviewRegressionTests.swift](../Tests/BlinkCoreTests/ReviewRegressionTests.swift).

## D3 — One due reminder, with no backlog

Priority is long break, movement break, eye break, then blink cue. A due higher-priority break consumes any coincident or already pending lower-priority break and restarts that schedule without adding a completion or skip. Snooze sets the pending schedule's target to current accrued time plus 300 seconds, including when the prompt has sat unanswered. Eye completion resets the eye schedule; movement completion resets eye and movement while preserving long-break progress; long completion resets all three. Skip or early end resets only that break's schedule. Suppressed blink cues are discarded. These choices avoid duplicate credit and immediate repeat prompts. See [ScheduleTests.swift](../Tests/BlinkCoreTests/ScheduleTests.swift) and [MovementTests.swift](../Tests/BlinkCoreTests/MovementTests.swift).

## D4 — Quiet mode preserves voluntary actions

Quiet mode suppresses automatic reminders while eligible time still counts. Entering quiet during an active break ends it early and records a skip, preventing an invisible countdown. Starting a break manually while already quiet shows that break and retains the quiet period afterward. Resume, observed quiet expiry, return from absence, and relaunch give ten seconds of grace before overdue presentation. Previews do not change schedules or counters. See [QuietModeTests.swift](../Tests/BlinkCoreTests/QuietModeTests.swift) and [AppModel.swift](../Sources/Blink/Application/AppModel.swift).

## D5 — Credit only observed absence, without double subtraction

Five minutes of input inactivity triggers idle detection and rollback bounded by counted time since the last input. Idle detection resets eye and movement schedules; 20 seconds of observed unavailability resets eye; a continuous absence reaching five minutes resets movement, and 15 minutes resets all three. Combined idle/lock/sleep stays one absence. Rollback cannot subtract sleep twice or reach across a reset, guided break, or relaunch. Natural absences never add guided completions. Idle detection is optional for quiet reading; lock/sleep monitoring remains active. See [AbsenceTests.swift](../Tests/BlinkCoreTests/AbsenceTests.swift).

An explicitly started countdown continues during observed lock/sleep. If it completes while unavailable, the timer completion can update the appropriate day's counter, but no sound is replayed on wake. A coarse tick assigns completion to when the countdown actually elapsed, including across midnight. See [CoarseTickTests.swift](../Tests/BlinkCoreTests/CoarseTickTests.swift).

## D6 — Protect saved data and onboarding

Decode failure never silently replaces a saved file. The app runs with temporary defaults and requires the user's explicit reset before saving again. Decodable invalid state is repaired conservatively. Applying settings preserves the existing onboarding flag, and only a changed schedule's timing or enablement restarts that schedule. Restore defaults cannot restart onboarding. See [AdapterTests.swift](../Tests/BlinkAppTests/AdapterTests.swift), [SettingsTests.swift](../Tests/BlinkCoreTests/SettingsTests.swift), and [InvalidStateTests.swift](../Tests/BlinkCoreTests/InvalidStateTests.swift).

## D7 — Keep reminders dismissible and keyboard reachable

Scheduled prompts do not take focus. Breaks use click-through dimmers and separate interactive controls on each display. The global Control–Option–Command–B shortcut deliberately opens the full menu; the app-local Show Current Reminder action focuses a pending prompt or opens the menu. One registered shortcut avoids monitoring ordinary keystrokes. Larger native action targets preserve keyboard and accessibility behavior. See [interface behavior](interface.md) and [GlobalShortcut.swift](../Sources/Blink/Platform/GlobalShortcut.swift).

## D8 — A blink must finish and release its window

Use a finite eye sequence ending fully open, with whole-panel fades and stationary text. Reduce Motion stops eye movement immediately; disabling it during that cue does not restart a partial blink. Scheduled arrivals while a cue is visible are discarded; explicit Preview may replace it. Cleanup has an identity-checked completion path and a bounded fallback so delayed callbacks cannot latch a cue or dismiss its replacement. Preserve separate tests for ordinary completion and fallback safety; do not extend the fallback deadline just to make an ordinary-path probe pass. See [interface timing](interface.md#blink-cue) and [BlinkAnimationTests.swift](../Tests/BlinkAppTests/BlinkAnimationTests.swift).

## D9 — Keep acceptance tied to the observed build

Deterministic days, native probes, physical observations, and resource recordings answer different questions. Overnight or partial runs do not establish a full working-day pass, and a new binary requires fresh normal-use evidence. See [verification](verification.md) for open acceptance checks. Offline use, no camera tracking, and no strict enforcement remain [explicit boundaries](requirements.md#explicit-boundaries). Preview downloads follow D12; package checks do not close the acceptance trial.

## D10 — Vary the cue without increasing disruption

Use four matching instruction, eye-pattern, and decorative-tint variants in a shuffled bag. Each appears once per cycle, with no immediate repeat across cycle boundaries. Select only when a cue is actually presented; suppressed arrivals do not consume variants. Use a larger fixed panel, eye, and type size at a fixed top-right position on the pointer's display, so the cue stays noticeable and predictable without moving across working content.

Variation keeps a repeated cue from becoming easy to ignore; it is presentation-only and does not measure habituation or actual blinking. All variants share `BlinkCore` scheduling, the silent three-second lifetime, click-through/no-focus behavior, primary instruction colors, Increased Contrast, and Reduce Motion handling. Each animated pattern finishes open; Reduce Motion displays a static open eye regardless of variant. See [R4](requirements.md#functional-requirements) and [interface behavior](interface.md#blink-cue).

## D11 — Add movement as an optional counted-time schedule

Movement is a third, optional break between eye and long breaks. When enabled, its starting preferences are 60 counted minutes, two minutes away, and a suggestion of 10 squats; users can choose another movement. Explicitly saved activity choices are preserved. These are habit preferences, with no repetition measurement or exercise-completion claim. Keep timer-based completion and End break, without a separate Done action.

Movement follows D3's priority and completion rules and D5's absence credit. Its completion preserves long-break progress because two minutes away is not the longer rest. Its five-minute absence reset is scheduling credit, not verified exercise, and natural absence adds no guided completions. Activity-only edits preserve schedule progress.

Preserve D6's protection of saved data: decode older version-1 states with movement disabled and fresh movement fields, while retaining all previously required data, onboarding, timers, and counters. Movement UI uses the native control targets and compact prompt of the other breaks, a green accent, the 42% click-through dimmer, a small visible countdown, the optional completion chime, and the same manual and quiet actions. See [R8](requirements.md#functional-requirements) and [interface behavior](interface.md#prompts-breaks-and-previews).

## D12 — Ship preview downloads without an Apple developer membership

Use the existing ad-hoc signature to distribute Apple silicon ZIP packages through GitHub Releases. Include the MIT license, checksum, and explicit first-launch guidance. The signature verifies bundle integrity but does not establish an Apple-verified developer identity, and the app is not notarized. Preserve the operating system's per-app approval flow; do not instruct recipients to disable Gatekeeper globally.

Build every package from a fresh bundle stamped with its channel, bundle version and source commit, and verify the extracted app before upload. Successful app-affecting `main` pushes replace one rolling Development pre-release that is never marked Latest; a version tag publishes a fixed numbered release marked Latest whose assets are never replaced. Because numbered releases publish immediately, review the download experience on a Development build first. Developer ID signing and notarization can be added when program membership is available. See [release downloads](releases.md).

## D13 — Protect process ownership and retain editor intent

Acquire an OS-backed lease on the selected state directory before constructing the model. Scope ownership by storage rather than bundle ID, so renamed forks cannot write the same file concurrently and isolated development stores remain usable. Keep the lock file after exit; kernel ownership, rather than file existence, determines whether another process may start.

Keep the Settings editor in a window-owned session and reuse its hosting view. Navigation and window close/reopen preserve even invalid partial input without applying it. Drafts last until app termination and are not added to persisted engine state. Save applies reminder edits, while launch-at-login remains immediate with explicit UI copy.

Keep scheduled reminders nonfocused while requesting transition-only accessibility announcements. Quiet/unavailable states suppress automatic prompt speech; explicit breaks retain their completion signal during quiet, matching existing chime semantics. Blink cues and previews remain silent. Preserve the existing registered physical shortcut and update its visual/spoken label from the current keyboard layout's Command table, rather than claiming the key is always B or observing ordinary input. See [interface behavior](interface.md) and [architecture](architecture.md).
