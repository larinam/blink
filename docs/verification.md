# Verification and acceptance

Blink is preview software. Automated checks cover deterministic behavior and packaging; native interaction, recipient installation, and normal-use acceptance require observations of the exact build being distributed. Commands are in [Development](development.md) and [Release downloads](releases.md).

## Automated coverage

| Check | What it establishes | Limits |
| --- | --- | --- |
| [Core suites](../Tests/BlinkCoreTests) | Deterministic portions of [acceptance 1–6](requirements.md#quality-and-acceptance-criteria): schedules, reminder priority, actions and counters, absence credit, quiet mode, persistence, and simulated day transitions. | Simulated clocks and state transitions do not exercise physical lock, sleep, displays, or native controls. |
| [App suites](../Tests/BlinkAppTests) | Availability integration, storage and state-directory ownership, Settings drafts, announcement decisions, and keyboard-layout translation. | Default execution skips the opt-in native UI checks. Announcement tests do not establish actual VoiceOver speech or braille output. |
| [Release automation checks](../scripts/test-release-workflows.py) | Change detection, package identity, stale-run handling, and failure ordering for Development publication. | Local service stand-ins do not verify GitHub checkout, artifact transfer, or release APIs. |
| [Package verification](../scripts/package-release.sh) | Fresh arm64 bundle, ad-hoc signature, ZIP extraction, executable bytes and permissions, license, instructions, build identity, and checksum. | Packaging does not launch the app, establish Apple notarization, or reproduce browser quarantine. |

CI runs the default tests and builds or packages the app. Check the relevant GitHub run for its result. Follow [AGENTS.md](../AGENTS.md) when changing workflows; local execution does not establish GitHub-hosted behavior.

## Manual acceptance

Treat these checks as open for a distributed build unless its verification evidence records them as completed:

- **Normal-use day (acceptance 8):** observe one unchanged build through a full working day, including naturally scheduled reminders, Start/Snooze/Skip/End controls, resource trends, sleep gaps, responsiveness, and overlay cleanup. Follow the [recording procedure](development.md#normal-use-working-day-recording).
- **Accessibility:** verify actual VoiceOver speech or braille while another app is frontmost, including the shortcut route and manually started breaks during quiet mode.
- **Recipient installation:** download through a browser and check quarantine, the per-app Open Anyway path, onboarding, menu controls, About identity, Quit, and relaunch. Follow the [release checklist](releases.md#check-the-recipient-experience).
- **Process ownership:** exercise the duplicate-startup modal alert; automated lease and contention checks do not cover the alert itself.
- **Displays and availability (acceptance 5 and 7):** exercise physical lock/unlock, sleep/wake, full-screen workspaces, display connection changes, and dismissible controls on each display after changes to those paths. Check silent completion during sleep as well as ordinary fade completion and safe fallback cleanup.
- **Workflow changes:** verify the intended PR merge checkout, main-push artifact handoff and Development update, docs-only publication skip, and numbered-tag release behavior on GitHub. Only perform publication checks when authorized; local test stand-ins are not a hosted execution result.

A passing timer test does not establish native acceptance, and an interrupted or partial recording does not establish a full working day.

## Availability limits

Sleep and display-sleep flags depend on workspace notifications. `AvailabilityClock` recovers suspension duration after a missed sleep notification. `SystemMonitor` clears a flag left set by a dropped wake notification once keyboard or pointer input arrives after it; until then, Blink keeps treating the Mac as unavailable. Include notification-loss cases when investigating availability failures; ordinary sleep/wake observations do not cover them automatically.

## Report a verification run

Keep results with the evidence in an ignored `qa-output/` directory, pull request, or release report. Record:

- Source revision, version/build, channel, and binary or downloaded ZIP checksum.
- macOS/toolchain, display or session prerequisites, commands, and relevant output.
- Passed, failed, skipped, simulated, and untested checks, with their limits.

Results apply to the observed build. Preserve the evidence before replacing its binary, and keep dated run inventories, machine-specific paths, and session transcripts out of these maintained guides.
