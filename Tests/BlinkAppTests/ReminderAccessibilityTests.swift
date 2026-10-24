import BlinkCore
import Carbon.HIToolbox
import Testing
@testable import Blink

@Suite("Reminder accessibility")
@MainActor
struct ReminderAccessibilityTests {
    @Test("A prompt announces once, again only after replacement or redisplay")
    func promptTransitions() {
        var spoken: [String] = []
        let announcer = ReminderAnnouncer { spoken.append($0) }
        announcer.updatePrompt(nil, openHint: "Open Blink.")
        announcer.updatePrompt(.short, openHint: "Press the shortcut to open Blink.")
        for _ in 0..<60 { announcer.updatePrompt(.short, openHint: "Press the shortcut to open Blink.") }
        #expect(spoken.count == 1)
        #expect(spoken[0].contains("eye break"))
        #expect(spoken[0].contains("Press the shortcut"))
        announcer.updatePrompt(.long, openHint: "Open Blink.")
        #expect(spoken.count == 2)
        #expect(spoken[1].contains("long break"))
        // Quiet, absence, preview or dismissal removes the visible prompt.
        announcer.updatePrompt(nil, openHint: "Open Blink.")
        #expect(spoken.count == 2)
        announcer.updatePrompt(.long, openHint: "Open Blink from the menu bar.")
        #expect(spoken.count == 3)
        #expect(spoken[2].contains("menu bar"))
    }

    @Test("Unavailable completion is silent and never replayed")
    func completionEligibility() {
        var spoken: [String] = []
        let announcer = ReminderAnnouncer { spoken.append($0) }
        announcer.completed(.short, unavailable: true)
        announcer.updatePrompt(nil, openHint: "Open Blink.")
        #expect(spoken.isEmpty)
        announcer.completed(.movement, unavailable: false)
        #expect(spoken == ["Movement break complete."])
    }

    @Test("An explicitly started break can announce completion during quiet mode")
    func manualQuietCompletion() {
        var spoken: [String] = []
        let announcer = ReminderAnnouncer { spoken.append($0) }
        let quiet = EngineSnapshot(settings: AppSettings(), summary: DailySummary(), status: .quiet,
                                   shortRemaining: 0, longRemaining: 7200, pendingBreak: .short,
                                   activeBreak: nil, isQuiet: true, quietUntil: nil)
        announcer.update(quiet, unavailable: false, previewing: false, openHint: "Open Blink.")
        #expect(spoken.isEmpty)
        announcer.completed(.short, unavailable: false)
        #expect(spoken == ["Eye break complete."])
    }

    @Test("Snapshot presentation gates keep quiet, idle, unavailable and previews silent")
    func presentationEligibility() {
        var spoken: [String] = []
        let announcer = ReminderAnnouncer { spoken.append($0) }
        func snapshot(status: EngineStatus = .running, quiet: Bool = false, active: ActiveBreak? = nil) -> EngineSnapshot {
            EngineSnapshot(settings: AppSettings(), summary: DailySummary(), status: status,
                           shortRemaining: 0, longRemaining: 7200, pendingBreak: .short,
                           activeBreak: active, isQuiet: quiet, quietUntil: nil)
        }
        for hidden in [snapshot(status: .quiet, quiet: true), snapshot(status: .idle),
                       snapshot(status: .onboarding), snapshot(status: .onBreak, active: ActiveBreak(kind: .long, remaining: 10))] {
            announcer.update(hidden, unavailable: false, previewing: false, openHint: "Open Blink.")
        }
        announcer.update(snapshot(), unavailable: true, previewing: false, openHint: "Open Blink.")
        announcer.update(snapshot(), unavailable: false, previewing: true, openHint: "Open Blink.")
        #expect(spoken.isEmpty)
        announcer.update(snapshot(), unavailable: false, previewing: false, openHint: "Open Blink.")
        #expect(spoken.count == 1)
        announcer.update(snapshot(status: .quiet, quiet: true), unavailable: false, previewing: false, openHint: "Open Blink.")
        #expect(spoken.count == 1)
        // On return, the one current prompt is announced; suppressed ticks add no backlog.
        announcer.update(snapshot(), unavailable: false, previewing: false, openHint: "Open Blink.")
        #expect(spoken.count == 2)
    }

    @Test("Shortcut descriptions follow layout changes without registering a hotkey")
    func shortcutLayoutLabel() {
        @MainActor final class Layout { var key: String? = "B" }
        let layout = Layout()
        let shortcut = GlobalShortcut(keyLabel: { layout.key })
        var changes: [ShortcutDescription] = []
        shortcut.onDescriptionChange = { changes.append($0) }
        #expect(shortcut.description.label == "⌃⌥⌘B")
        layout.key = "X" // Physical U.S. B is X in Dvorak.
        shortcut.refreshDescription()
        #expect(shortcut.description.label == "⌃⌥⌘X")
        #expect(shortcut.description.spoken == "Control–Option–Command–X")
        shortcut.refreshDescription()
        #expect(changes.count == 1)
        layout.key = "B" // Russian and Dvorak–QWERTY Command use a Latin Command table.
        shortcut.refreshDescription()
        #expect(shortcut.description.label == "⌃⌥⌘B")
        layout.key = nil
        shortcut.refreshDescription()
        #expect(shortcut.description.label.contains("B-position"))
        #expect(shortcut.description.spoken.contains("U.S. keyboard"))
        #expect(changes.count == 3)
    }

    @Test("Native layouts label the physical shortcut using their Command tables")
    func nativeLayoutTranslation() throws {
        for (identifier, expected) in [("com.apple.keylayout.US", "B"), ("com.apple.keylayout.Dvorak", "X"),
                                       ("com.apple.keylayout.DVORAK-QWERTYCMD", "B"), ("com.apple.keylayout.Russian", "B")] {
            let query = [kTISPropertyInputSourceID as String: identifier] as CFDictionary
            let layouts = try #require(TISCreateInputSourceList(query, true).takeRetainedValue() as? [TISInputSource])
            let source = try #require(layouts.first)
            #expect(GlobalShortcut.keyLabel(for: source) == expected)
        }
        // Querying layouts above never selects them or changes the user's input source.
    }
}
