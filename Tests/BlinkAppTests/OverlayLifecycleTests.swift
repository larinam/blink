import AppKit
import BlinkCore
import Testing
@testable import Blink

/// Opt-in native window checks. These briefly show this test process's overlays on
/// the currently connected displays; they never change display or system settings.
@Suite("Native overlay lifecycle", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["BLINK_NATIVE_CHECKS"] == "1"))
struct OverlayLifecycleTests {
    @Test("Every attached screen has dismissible controls and a click-through dimmer", arguments: [BreakKind.short, .movement, .long])
    @MainActor
    func connectedDisplaysAndRecreation(kind: BreakKind) throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let baseline = Set(app.windows.map(ObjectIdentifier.init))
        let screens = NSScreen.screens
        #expect(!screens.isEmpty)
        let overlays = OverlayController()
        defer { overlays.hideAll() }
        overlays.showBreak(kind: kind, remaining: 90, duration: 900)
        let first = visiblePanels(excluding: baseline)
        #expect(first.count == screens.count * 2)
        for screen in screens {
            let dimmer = try #require(first.first { $0.ignoresMouseEvents && $0.frame == screen.frame })
            #expect(!dimmer.canBecomeKey)
            #expect(dimmer.backgroundColor.alphaComponent > 0 && dimmer.backgroundColor.alphaComponent < 1)
            let control = try #require(first.first { !$0.ignoresMouseEvents && screen.visibleFrame.contains($0.frame) })
            #expect(control.canBecomeKey)
            #expect(control.contentView != nil)
            #expect(control.collectionBehavior.contains(.fullScreenAuxiliary))
        }
        overlays.displaysChanged()
        let recreated = visiblePanels(excluding: baseline)
        #expect(recreated.count == screens.count * 2)
        #expect(first.allSatisfy { !$0.isVisible })
        let firstIDs = Set(first.map(ObjectIdentifier.init))
        #expect(recreated.allSatisfy { !firstIDs.contains(ObjectIdentifier($0)) })
        overlays.hideAll()
        #expect(visiblePanels(excluding: baseline).isEmpty)
        print("Verified overlay creation, recreation and cleanup on \(screens.count) attached displays.")
    }

    @Test("Blink cue stays on one display, cannot take focus, and cleans itself up")
    @MainActor
    func blinkCueLifecycle() throws {
        // A separate native event loop is necessary: Swift Testing's executor
        // cannot stand in for NSApplication.run() for animation completions.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [root.appendingPathComponent("scripts/check-blink-animation.sh").path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let report = String(decoding: data, as: UTF8.self)
        print(report)
        #expect(process.terminationStatus == 0, Comment(rawValue: report))
    }

    @Test("All break previews close without leaving any windows")
    @MainActor
    func previewLifecycle() {
        let baseline = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
        let overlays = OverlayController()
        defer { overlays.hideAll() }
        overlays.previewBreak(.short)
        #expect(overlays.isPreviewing)
        overlays.endPreview()
        #expect(!overlays.isPreviewing)
        #expect(visiblePanels(excluding: baseline).isEmpty)
        overlays.previewBreak(.movement)
        #expect(overlays.isPreviewing)
        overlays.endPreview()
        #expect(!overlays.isPreviewing)
        #expect(visiblePanels(excluding: baseline).isEmpty)
        overlays.previewBreak(.long)
        #expect(overlays.isPreviewing)
        RunLoop.main.run(until: Date().addingTimeInterval(5.3))
        #expect(!overlays.isPreviewing)
        #expect(visiblePanels(excluding: baseline).isEmpty)
    }

    @MainActor
    private func visiblePanels(excluding baseline: Set<ObjectIdentifier>) -> [NSWindow] {
        NSApplication.shared.windows.filter {
            $0 is ReminderPanel && $0.isVisible && !baseline.contains(ObjectIdentifier($0))
        }
    }
}
