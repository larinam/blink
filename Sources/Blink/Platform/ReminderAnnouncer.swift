import AppKit
import BlinkCore

/// Announces transitions, never countdown ticks or silent blink cues. Posting an
/// accessibility announcement leaves focus alone and does nothing without VoiceOver.
@MainActor
final class ReminderAnnouncer {
    private let speak: @MainActor (String) -> Void
    private var visiblePrompt: BreakKind?

    init(speak: @escaping @MainActor (String) -> Void = ReminderAnnouncer.post) {
        self.speak = speak
    }

    func update(_ snapshot: EngineSnapshot, unavailable: Bool, previewing: Bool, openHint: String) {
        let canPresent = !unavailable && !previewing && snapshot.activeBreak == nil
            && snapshot.status != .idle && snapshot.status != .onboarding && !snapshot.isQuiet
        updatePrompt(canPresent ? snapshot.pendingBreak : nil, openHint: openHint)
    }

    func updatePrompt(_ kind: BreakKind?, openHint: String) {
        guard kind != visiblePrompt else { return }
        visiblePrompt = kind
        if let kind { speak("Your \(kind.title.lowercased()) is ready. \(openHint) Choose Start, Snooze, or Skip.") }
    }

    func completed(_ kind: BreakKind, unavailable: Bool) {
        // Quiet mode still permits explicitly started breaks and their chime.
        // Give VoiceOver the same completion signal for those voluntary breaks.
        if !unavailable { speak("\(kind.title) complete.") }
    }

    private static func post(_ text: String) {
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}
