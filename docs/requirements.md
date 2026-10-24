# Blink — product requirements

Product behavior and acceptance criteria. Settled interpretations are in [decisions](decisions.md); how criteria are verified and which remain open is in [verification](verification.md).

## Summary

Blink is a native Mac menu bar app for personal use that encourages regular eye breaks, optional movement breaks, complete blinking, and a comfortable screen setup.

Blink uses scheduled reminders, gentle overlays, and local storage. Its interaction references are [LookAway](https://lookaway.com/), [BlinkMate](https://apps.apple.com/us/app/blinkmate/id6756325660), and [Blinker](https://www.getblinker.app/).

## Functional requirements

**R1 — Menu bar operation**

- Run in the menu bar without a persistent Dock icon.
- Show whether reminders are running, quiet, idle, or on a break, plus time until eye, movement, and long breaks in fixed-order rows and a next-break summary.
- Provide Start eye break, Move now, Start long break, Quiet mode, Settings, Today, and Quit. Move now is enabled when movement reminders are enabled.
- Begin scheduling after onboarding. Offer an optional launch-at-login setting.

**R2 — Short eye breaks**

- Default: after **20 minutes of counted screen time**, invite the user to look at something approximately **20 feet / 6 metres away for 20 seconds**.
- Show a compact, nonblocking prompt with **Start**, **Snooze 5 minutes**, and **Skip**. Never take keyboard focus automatically.
- Request a one-time VoiceOver announcement when a break prompt becomes visible, including how to open Blink. Announce completion while available, including a break started manually during quiet mode; do not announce silent blink cues or previews.
- Start the break countdown only when the user chooses Start.
- During the break, gently dim every connected display and show simple guidance, remaining time, and an accessible End break control.
- Signal completion with a brief chime, enabled by default and independently configurable, so the user can look away throughout the break.

**R3 — Longer breaks**

- Default: request a **15-minute break after 120 minutes of counted screen time**.
- Short breaks pause the long-break timer but do not reset it.
- Use the same prompt and countdown interaction as short breaks, with guidance to step away from screens.
- A completed long break resets all three break schedules.

These defaults follow [AOA guidance](https://www.aoa.org/healthy-eyes/eye-and-vision-conditions/computer-vision-syndrome). Present them as supportive habits, without promising prevention or treatment of eye conditions.

**R4 — Blink reminders**

- Show a compact, legible, silent visual cue every **60 seconds of counted screen time**.
- Vary displayed cues among four matching instructions and gentle eye patterns: one deliberate full blink, two full blinks, a brief full closure, and one soft full blink. Use a shuffled cycle that shows each variant once and never repeats the same variant on consecutive presentations, including across cycle boundaries.
- Use a larger fixed layout with decorative accent variation; keep instruction text in the primary system label color and honour Increased Contrast.
- Fade the stationary cue in, show a finite eye sequence that returns to an open eye, then fade the cue out. Keep its text readable and still throughout the roughly three-second presentation.
- With Reduce Motion enabled, show a static open eye with fades only. Honour preference changes without relaunching.
- Display the cue at a fixed top-right position on one display—the display containing the pointer—without dimming the workspace, intercepting clicks, or taking focus.
- Suppress cues during break prompts, active breaks, quiet mode, and inactivity. Discard missed cues.
- If a very short interval expires while a cue is still visible, discard that arrival so the current blink can finish. An explicit Preview may restart it.
- Allow the interval to be changed and the feature disabled independently.
- Describe the interval as a reminder preference, not a target blink rate.
- Do not measure or claim to verify blinks. Avoid presenting a universal 70% reduction: research shows that blink behavior varies with task conditions and that incomplete blinking also matters. [Blink-pattern study](https://pubmed.ncbi.nlm.nih.gov/24413278/)

**R5 — Screen setup guidance**

- Include a short onboarding checklist, available again through Settings.
- Explain positioning the **screen centre approximately 4–5 inches / 10–13 cm below eye level**, rather than positioning the screen’s top edge at that height.
- Suggest a viewing distance of approximately **20–28 inches / 50–70 cm** and reducing uncomfortable glare. [AOA guidance](https://www.aoa.org/healthy-eyes/eye-and-vision-conditions/computer-vision-syndrome)
- Use self-check instructions; Blink does not assess posture or screen position automatically.

**R6 — Settings and quiet mode**

- Allow independent enable/disable controls and timing adjustments for eye, movement, and long breaks, and blink cues.
- Provide Restore recommended defaults and a preview of each reminder.
- Reject zero or negative timing values. Changing timing settings restarts the affected schedule.
- Preserve unsaved reminder edits across page navigation and closing/reopening Settings until the app quits. Label launch-at-login as immediate; reminder edits require Save.
- Offer quiet mode for **15, 30, or 60 minutes**, or until manually resumed.
- Quiet mode hides automatic reminders while eligible screen time continues to accumulate. Entering quiet during an active break ends it early and records a skip. A break started manually while already quiet remains visible and preserves the quiet period afterward.
- Show quiet status and its expiry in the menu bar.

**R7 — Daily summary and privacy**

- Show today’s timed eye, movement, and long breaks completed, skipped breaks, and snooze actions.
- Ending a started break early counts as skipped; each snooze action is counted separately.
- Describe completion as a finished timer, without claiming that gaze, blinking, or actual rest was verified.
- Natural absences affect scheduling but do not count as completed guided breaks.
- Keep settings, timer state, and today’s counters locally. Retain no historical daily records.
- Refuse a second process using the same state directory before it can load or save state; distinct development directories remain independent.
- Require no account, backend, telemetry, camera, microphone, or screen recording.

**R8 — Optional movement breaks**

- Default off until enabled, including when loading saved state that has no movement settings. Preserve onboarding, existing settings, timer progress, and counters.
- When enabled: invite a movement break after 60 counted screen minutes, with a configurable two-minute period away from screens. Suggest 10 squats; allow sit-ups, walking, stretching, or simply stepping away instead. Activity and duration are user preferences.
- Use the existing nonblocking Start / Snooze 5 minutes / Skip prompt. Start dims displays with static guidance, a small visible timer, optional completion chime, and End break / Escape.
- Changing only the activity does not restart the schedule. Movement completion resets movement and eye schedules while preserving long-break progress. Repetitions are never measured or counted, and there is no separate Done action.

## Scheduling rules

- **Counted screen time:** time while the app is running, the Mac is unlocked, its display is awake, and the user is not in an active break or detected idle period.
- **Idle detection:** after five minutes without keyboard or pointer input, treat the absence as beginning at the last input. Remove that interval from counted screen time and stop reminders until activity resumes.
- A detected idle absence resets eye and movement schedules; an observed absence of at least five minutes resets movement, and at least 15 minutes resets all three schedules. This is scheduling credit, not verified movement.
- Explain that inactivity is only an approximation and can include quiet reading. Allow idle detection to be disabled; lock and sleep detection remain active.
- Lock and sleep pause counting immediately. An observed absence of at least 20 seconds resets the eye schedule; five minutes resets movement; 15 minutes resets all.
- **Reminder priority:** long break, movement break, eye break, then blink cue. Present only one reminder at a time. A higher-priority due break consumes coincident lower-priority occurrences without completion or skip counters.
- **Snooze:** defer that occurrence by five counted minutes from the user’s action, even if the prompt was left unanswered. **Skip:** dismiss it and schedule its next normal interval, without recording rest. A short-break action never resets the long-break schedule.
- An unanswered prompt remains available without repeated animations, sounds, or automatic countdown starts.
- After quiet mode or inactivity ends, allow ten seconds before showing an overdue prompt. Show only the highest-priority due break; never replay a backlog.
- Preserve settings, counters, and schedule progress across relaunches. Time while the app was closed is neither counted screen time nor credited rest.
- Reset today’s summary at local midnight without resetting ongoing break schedules.

## Quality and acceptance criteria

- Support **Apple silicon Macs running macOS 26** or later.
- Use native controls, light and dark appearance, keyboard navigation, VoiceOver labels, and Reduce Motion support.
- Keep End break available throughout every break. Do not block input outside the app’s own controls.
- Handle multiple displays, full-screen workspaces, and display connection changes without stranded overlays.
- Operate offline and avoid continuous rendering between reminders.

Acceptance checks:

1. At default settings, eye breaks become due after 20 counted minutes and long breaks after 120. When enabled, movement becomes due after 60; eye breaks do not erase movement or long-break progress.
2. Simultaneous reminders produce one appropriate prompt.
3. Start, snooze, skip, early exit, and completion update schedules and daily counters correctly.
4. Five-minute and 15-minute idle periods receive the specified scheduling credit; disabling idle detection preserves quiet reading time.
5. Lock, sleep, wake, relaunch, and midnight transitions preserve the intended timer behavior.
6. Quiet mode suppresses automatic reminders while counting eligible time; manually started breaks preserve quiet, and resuming produces no reminder burst.
7. Break overlays work across connected displays, remain dismissible, and leave no windows behind.
8. A full working-day trial shows reliable reminders, responsive controls, and no steadily increasing resource usage.

## Explicit boundaries

Blink is English-only, displays both metric and imperial guidance, and is intended for personal installation.

Camera tracking, strict enforcement, automatic meeting detection, app exclusions, system Focus integration, weekly trends, cloud sync, and payments are deferred. No public API or external integration is required.

Preview app downloads are packaged for GitHub Releases with an ad-hoc signature, a SHA-256 checksum, and explicit first-launch instructions. Apple Developer Program membership is not required for this distribution path. Developer ID signing and Apple notarization are deferred; recipients must approve an unidentified app where macOS policy permits. See [release downloads](releases.md).
