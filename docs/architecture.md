# Architecture

Blink is a dependency-free Swift package targeting macOS 26. The bundle script builds for Apple silicon. [Package.swift](../Package.swift) declares the `BlinkCore` library, `Blink` executable, and separate core and app test targets.

## Modules and data flow

`Sources/Blink/` is organized into `Application/` for lifecycle and engine coordination, `Platform/` for macOS services and storage, and `UI/` for views, styling, and overlays. These are folders within the same executable target; they do not introduce module boundaries. `Sources/BlinkCore/` and the two matching test directories retain the standard Swift package layout.

`Packaging/Info.plist` supplies app bundle metadata to `scripts/build.sh`. The standalone Swift programs in `Tools/` generate the icon and run the native animation probe; they are compiled or interpreted by the scripts, independently of the package targets.

`scripts/package-release.sh` assembles a fresh bundle stamped with its channel, bundle version and source commit, renders `Packaging/INSTALL.md`, and verifies the ZIP, checksum and `build-info.json`. The tag-triggered `.github/workflows/release.yml` runs default tests and publishes a fixed numbered release from those artifacts. See [release downloads](releases.md) for the ad-hoc signing and first-launch limits.

`.github/workflows/ci.yml` runs default tests and the release bundle build for pull requests targeting `main` and pushes to `main`. Its **Test and build** job uses read-only repository access and no secrets. On `main`, `scripts/development-changes.sh` decides whether app-affecting paths changed since the `development` tag; if so, a separate write-scoped job publishes the rolling Development pre-release. See [continuous integration](development.md#continuous-integration).

| Area | Responsibility | Source |
| --- | --- | --- |
| Scheduling | Pure state transitions, reminder priority, absence credit, counters, and validation | [ReminderEngine.swift](../Sources/BlinkCore/ReminderEngine.swift), [AppSettings.swift](../Sources/BlinkCore/AppSettings.swift) |
| State contract | Codable persistence value, derived snapshot, transient effects | [EngineState.swift](../Sources/BlinkCore/EngineState.swift), [EngineSnapshot.swift](../Sources/BlinkCore/EngineSnapshot.swift), [EngineEffect.swift](../Sources/BlinkCore/EngineEffect.swift) |
| Integration | Clock sampling, engine commands, publishing, persistence, sound, login status | [AppModel.swift](../Sources/Blink/Application/AppModel.swift) |
| OS availability | Session, lock, sleep, display, and elapsed input inactivity observations | [SystemMonitor.swift](../Sources/Blink/Platform/SystemMonitor.swift), [AvailabilityClock.swift](../Sources/Blink/Platform/AvailabilityClock.swift) |
| Presentation | Menu bar lifecycle, menu/settings views, overlays, finite blink cue | [BlinkApp.swift](../Sources/Blink/Application/BlinkApp.swift), [OverlayController.swift](../Sources/Blink/UI/OverlayController.swift), [BlinkCueView.swift](../Sources/Blink/UI/BlinkCueView.swift) |
| Storage and shortcut | Versioned local JSON and one registered global shortcut | [StateStore.swift](../Sources/Blink/Platform/StateStore.swift), [GlobalShortcut.swift](../Sources/Blink/Platform/GlobalShortcut.swift) |
| Process ownership | Exclusive startup lease for each state directory | [StateDirectoryLock.swift](../Sources/Blink/Platform/StateDirectoryLock.swift) |
| Editor lifetime and accessibility | Window-owned drafts/navigation and transition announcements | [AppWindowSession.swift](../Sources/Blink/UI/AppWindowSession.swift), [ReminderAnnouncer.swift](../Sources/Blink/Platform/ReminderAnnouncer.swift) |

`BlinkCore` imports Foundation only. The adapter supplies wall time, elapsed duration, unavailable duration, input inactivity, and current availability to `tick`. The engine does not observe the OS, start timers, render, or access disk. Tests inject these inputs and a calendar.

The engine exposes `state` for persistence and `snapshot` for presentation. The snapshot includes settings, today's counters, status, remaining schedule time, presentable pending break, active countdown, and quiet status. Persistent UI follows the snapshot; `.blink` and `.breakCompleted` are transient effects. The adapter plays a completion sound only when enabled and available.

User actions tick first, apply an engine command, then publish and save. Preview windows are presentation state and never add completions, skips, or snoozes. Launch-at-login status comes from the OS and is outside `AppSettings`.

## Time and availability

`AppModel` runs a one-second common-mode timer with 0.15-second tolerance and also ticks at OS availability transitions. `AvailabilityClock` compares continuous and suspending clocks to recover system suspension, including a missed sleep notification. A stalled run loop alone does not become rest credit. The previous availability state partitions observed unavailable time; current availability controls presentation.

`SystemMonitor` reads elapsed time since input events without installing an event tap or reading key contents. It observes workspace/session notifications and reconciles the session dictionary. A successful dictionary without the lock flag means unlocked; a failed query retains the last known state. Sleep/display-sleep flags still rely on notifications. See [decisions](decisions.md) and [verification](verification.md) for evidence limits.

Wall time controls local-day rollover and timed quiet expiry. Continuous elapsed time controls countdowns, absences, and resume grace. Only eligible screen time advances reminder schedules. The [requirements](requirements.md#scheduling-rules) define those rules.

## Publishing and windows

The adapter avoids invalidating hidden views every second: it publishes semantic changes, minute changes, explicit refreshes, and updates needed by the open interface. Active overlay countdowns use their own observed model. `OverlayController` owns all prompt, countdown, dimmer, preview, and blink windows; display changes reconstruct active break windows and dismiss obsolete prompt/cue windows.

When unavailable, the adapter hides overlays. Otherwise an explicit active break takes presentation precedence over quiet mode. [Interface behavior](interface.md) defines focus, dismissal, pointer targets, and animation cleanup.

The main window retains one hosting view and an `AppWindowSession`. Its `SettingsEditor` outlives conditional Settings/Today/Guide views and window close/reopen, keeping incomplete text without applying it. Saved settings refresh a clean draft; a dirty draft stays untouched. Drafts are not persisted across app termination. Launch-at-login still applies immediately and is labelled separately from reminder edits.

`ReminderAnnouncer` posts an application-level accessibility announcement only when the visible pending break changes or a break completes while available. Prompt presentation gates exclude previews, idle, onboarding, quiet and unavailable states; a manually started break can announce completion during quiet, matching its chime. Blink cues remain silent. It does not move focus. The global shortcut translates only its registered physical key through the current keyboard layout's Command table and refreshes its display/spoken description on input-source changes.

## Persistence and recovery

`StateStore` writes a version-1 envelope containing `EngineState` to `~/Library/Application Support/Blink/state.json`, or the process-specific `BLINK_STATE_DIR`. Writes are atomic; directory creation requests mode `0700`, and the saved file is set to `0600`. Saves occur about every 15 seconds, on effects and user actions, and at orderly startup/shutdown. An abrupt exit can lose progress since the last save.

Before constructing `AppModel`, the application acquires an exclusive nonblocking `flock` on `.instance.lock` in that directory and retains the descriptor through the app run loop. Contention or an inaccessible directory prevents startup. The lock file stays in place to avoid inode replacement races; the kernel releases ownership on process exit, so a leftover file needs no cleanup. The descriptor is close-on-exec. Distinct development state directories have independent leases, even when bundle identifiers match.

A missing file starts defaults. Malformed, unreadable, or unsupported-version data activates temporary defaults and disables persistence until the user explicitly resets the saved data in Settings. The existing file remains untouched. Successfully decoded but semantically invalid fields are normalized by the engine.

Version-1 state includes movement's independent schedule, activity preference, and daily completion counter. Explicit decoders require the other non-optional fields and supply conservative defaults when movement fields are missing: movement disabled, 60-minute interval, two-minute duration, squats, and zero movement completions. State saved without movement fields loads without resetting onboarding or existing timer progress. Explicitly saved activities remain unchanged. Activity-only edits do not restart a schedule. Break presentation strings live in the app target, outside the Foundation-only core.

Relaunch restores saved schedule and active-break progress. Closed-app time earns neither counted time nor rest; a countdown resumes from its saved remainder. The engine clears transient absence tracking, applies launch grace, reconciles quiet expiry, and rolls today's summary using the current calendar. No historical daily log is stored by the app.
