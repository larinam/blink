# Interface behavior

The [requirements](requirements.md) define product behavior. This guide captures presentation details that matter when changing the native views.

## Prompts, breaks, and previews

A scheduled prompt is nonblocking and does not take keyboard focus. It stays available until Start, Snooze 5 minutes, or Skip. Start begins the countdown. The global shortcut opens the menu; Show Current Reminder focuses a pending prompt when one exists.

Settings keeps unsaved text and reminder choices while navigating between pages or closing/reopening the window. The footer marks unsaved edits and explains that they last until Blink quits. Save applies reminder edits; Restore recommended defaults remains an explicit immediate action. Launch at login applies immediately, with an explanation beside its toggle.

Movement uses that same 356 × 254-point prompt with a static standing-figure glyph, green accent, the chosen activity, and a duration-labelled Start action. Its started break keeps a smaller visible timer and states whether a completion chime will play. End break and Escape remain available; dimming stays at 42% black and does not block other apps. Movement previews use the draft activity without saving it and close after five seconds without changing schedules or counters.

The menu lists Eye, Movement, and Long in a fixed order with right-aligned countdowns, plus a summary of the next enabled break. A pending break takes priority over the manual actions and keeps Start, Snooze, and Skip. Rest your eyes now, Move now, and Start a long break are available otherwise; Move now is disabled while movement reminders are off. Settings places Movement between Eye and Long. Today reports timer completions and never counts repetitions.

Send feedback has its own full-width menu row and opens the Feedback page, also available from the sidebar before or after onboarding. The page shows blink@wellkernel.com as selectable text, Open email app, Open Gmail, and Copy email address. Email and Gmail links prefill the recipient and subject “Blink feedback” with no body or attachments. The Gmail HTTPS route bypasses a browser registered as the mailto handler without a working compose route. A rejected URL shows an inline message, and the other options remain available even when macOS reports a successful handoff without a draft. Copy writes only on click, shows confirmation until the next action, and announces it to VoiceOver. Blink changes no mail or browser defaults.

A started break has a click-through dimmer and a separate countdown/control panel on every connected display. End break remains accessible; Escape ends a focused break. The dimming layer leaves the workspace clickable. Display changes rebuild active break windows; lock/sleep hides overlays while the engine maintains countdown state. Break previews close after five seconds; blink previews use the normal three-second cue. Neither affects summary counters.

## Pointer targets and accessibility

Menu/reminder actions, sidebar rows, and guide links have measured 44-point-high targets. Padding and interaction shapes belong inside native labels, making the padded region actionable. Secondary actions have visible borders; Snooze and Skip occupy a separate row beneath Start. Sidebar rows use full-width targets and hover feedback. Quiet until resumed uses an infinity button with a descriptive accessibility label and tooltip.

This is Blink's chosen sizing policy for these controls, not a blanket minimum for every macOS control. Preserve native buttons/links, keyboard dispatch, VoiceOver labels, visible press states, and the gap between adjacent actions. The reminder panel is 254 points high; the countdown panel is 360 points high and reserves two lines for guidance. See [Design.swift](../Sources/Blink/UI/Design.swift), [MenuView.swift](../Sources/Blink/UI/MenuView.swift), [SettingsView.swift](../Sources/Blink/UI/SettingsView.swift), and [HitTargetTests.swift](../Tests/BlinkAppTests/HitTargetTests.swift).

Newly visible break prompts request one medium-priority VoiceOver announcement containing the break kind and how to open Blink. Repeated timer ticks do not repeat it; a replacement prompt or one redisplayed after suppression can announce again. Timer completion also announces while available, independently of the chime preference, including breaks started manually during quiet mode. Previews and blink cues do not announce, and no speech is replayed after unavailability. Announcements leave keyboard focus alone. The global shortcut's visual and spoken descriptions follow the current keyboard layout's Command table; if its key cannot be translated, Settings describes the physical U.S. B position explicitly. From another app, use that global shortcut to reach the menu's Start/Snooze/Skip controls; Show Current Reminder is app-local.

## Blink cue

The silent 232 × 64-point panel appears only on the pointer's display, at a fixed top-right position inset 24 points from its visible frame. Its layout pairs a 38 × 28-point eye with a semibold Title 2 instruction and a Body detail line, inside 16-point rounded corners. Both lines use the primary system label color because they form one instruction; variant tints are confined to the decorative eye. Increased Contrast uses the primary label color for the eye and strengthens the outline. The opaque system background keeps the cue readable over desktop content. It ignores clicks and cannot become key. Its instruction stays stationary while a vector eyelid clips a round pupil; the pupil does not squash. The finite eye animation runs only during a cue.

Each presented cue draws from a shuffled bag of four variants. Each variant appears once per cycle, with no consecutive repeat even across cycle boundaries. Discarded automatic arrivals do not consume a variant; an explicit Preview may replace the cue and draws the next variant. The larger size and position stay fixed rather than adding spatial movement.

| Instruction | Detail | Decorative tint | Eye pattern |
| --- | --- | --- | --- |
| Blink fully | and deliberately. | Green | One deliberate full blink |
| Two slow blinks | all the way closed. | Teal | Two full blinks |
| Close your eyes | for a moment. | Indigo | One full closure with a longer hold |
| Blink softly | and relax your face. | Amber | One gentler full blink |

This treatment follows Apple's [label color guidance](https://developer.apple.com/design/human-interface-guidelines/labels), [macOS typography](https://developer.apple.com/design/human-interface-guidelines/typography), and [contrast guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility). The cue is informational content, so it does not use the Liquid Glass styling reserved for controls and navigation in the [materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials). The Settings Preview action remains a native bordered button with its existing target size and accessibility label.

| Phase | Seconds from presentation |
| --- | --- |
| Whole-panel fade in, including shadow | 0–0.22 |
| Open eye settles (all variants) | 0–0.45 |
| Variant's finite eye sequence | See below |
| Fully open eye with stationary text | End of reopening–2.72 |
| Whole-panel fade out | 2.72–3.00 |

All times below are seconds from presentation. Every pattern ends fully open before fade-out; the two-blink pattern also stays open between 1.15 and 1.37 seconds.

| Variant / blink | Lids close | Fully closed | Lids reopen |
| --- | --- | --- | --- |
| Blink fully | 0.45–0.63 | 0.63–0.75 | 0.75–1.03 |
| Two slow blinks / first | 0.45–0.69 | 0.69–0.83 | 0.83–1.15 |
| Two slow blinks / second | 1.37–1.61 | 1.61–1.75 | 1.75–2.07 |
| Close your eyes | 0.45–0.75 | 0.75–1.45 | 1.45–1.85 |
| Blink softly | 0.45–0.71 | 0.71–0.81 | 0.81–1.19 |

Reduce Motion keeps every variant's eye static and open while retaining fades and varied instructions. Enabling it during a cue stops eye movement immediately; disabling it again allows movement only on a fresh cue. The menu also refreshes its Reduce Motion preference on presentation.

Fade completion removes the cue. A common-mode fallback timer is anchored to the actual fade start plus 0.28 seconds of fade and 0.12 seconds of allowance. Both cleanup paths check panel identity; successful completion invalidates the fallback. Prompts, breaks, display changes, and availability dismissal cancel immediately. An automatic cue arriving while another is visible is discarded; an explicit preview may restart it.

[OverlayController.swift](../Sources/Blink/UI/OverlayController.swift) owns fades and cleanup; [BlinkCueView.swift](../Sources/Blink/UI/BlinkCueView.swift) owns the eye. The [development guide](development.md#native-ui-checks) explains verification. Preserve the distinction between a safe fallback cleanup and evidence that ordinary animation completion ran. [BlinkAnimationTests.swift](../Tests/BlinkAppTests/BlinkAnimationTests.swift) and [OverlayLifecycleTests.swift](../Tests/BlinkAppTests/OverlayLifecycleTests.swift) cover the sequence, cleanup and native fade probe.
