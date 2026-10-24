import AppKit
import BlinkCore
import SwiftUI
import Testing
@testable import Blink

@Suite("Native Settings draft lifetime", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["BLINK_HIT_CHECKS"] == "1"))
struct SettingsWindowTests {
    @Test("Draft text survives native page removal and window close/reopen")
    @MainActor
    func draftSurvivesNativeLifecycle() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BlinkDraftWindow-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StateStore(directory: directory)
        let model = AppModel(store: store)
        defer { model.stop() }
        let session = AppWindowSession(settings: model.snapshot.settings)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 850, height: 720),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let hosting = NSHostingView(rootView: AppWindowView(model: model, session: session))
        window.contentView = hosting
        window.orderFrontRegardless()
        settle(hosting)
        // Change an actual AppKit-backed SwiftUI text field, not just the model.
        let interval = try #require(fields(hosting).first { $0.stringValue == "20" })
        interval.stringValue = "unfinished"
        interval.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: interval))
        settle(hosting)
        #expect(session.settings.draft.shortInterval == "unfinished")
        session.selection = .today
        settle(hosting)
        session.selection = .settings
        settle(hosting)
        #expect(fields(hosting).contains { $0.stringValue == "unfinished" })
        window.close()
        window.orderFrontRegardless()
        settle(hosting)
        #expect(fields(hosting).contains { $0.stringValue == "unfinished" })
        #expect(model.snapshot.settings.shortInterval == 1200)
        #expect(session.settings.hasUnsavedChanges)
    }

    @MainActor
    private func fields(_ view: NSView) -> [NSTextField] {
        view.subviews.flatMap { child in
            (child as? NSTextField).map { [$0] } ?? []
        } + view.subviews.flatMap { fields($0) }
    }

    @MainActor
    private func settle(_ view: NSView) {
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        view.layoutSubtreeIfNeeded()
    }
}
