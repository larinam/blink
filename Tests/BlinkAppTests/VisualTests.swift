import AppKit
import BlinkCore
import SwiftUI
import Testing
@testable import Blink

/// Optional, offscreen native renders for visual inspection in both appearances.
/// They never change the user's system appearance or order a window onscreen.
@Suite("Native visual renders", .serialized)
struct VisualTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["BLINK_RENDER_DIR"] != nil))
    @MainActor
    func renderScreens() throws {
        let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["BLINK_RENDER_DIR"]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stateDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BlinkRenders-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: stateDirectory) }
        let store = StateStore(directory: stateDirectory)
        let now = Date()
        var engine = ReminderEngine(now: now)
        engine.completeOnboarding(now: now)
        var settings = engine.snapshot.settings
        settings.movementEnabled = true
        try engine.updateSettings(settings, now: now)
        engine.startBreak(.short, now: now)
        engine.tick(now: now.addingTimeInterval(20), elapsed: 20, unavailableElapsed: 0, idleSeconds: 0, isUnavailable: false)
        try store.save(engine.state)
        let model = AppModel(store: store)
        _ = NSApplication.shared
        for (name, scheme, appearance) in [("light", ColorScheme.light, NSAppearance.Name.aqua), ("dark", ColorScheme.dark, NSAppearance.Name.darkAqua)] {
            try render(AppWindowView(model: model, selection: .settings), size: NSSize(width: 850, height: 720), scheme: scheme, appearance: appearance, to: directory.appendingPathComponent("settings-\(name).png"))
            try render(AppWindowView(model: model, selection: .feedback), size: NSSize(width: 850, height: 708), scheme: scheme, appearance: appearance, to: directory.appendingPathComponent("feedback-\(name).png"))
            try render(AppWindowView(model: model, selection: .today), size: NSSize(width: 850, height: 720), scheme: scheme, appearance: appearance, to: directory.appendingPathComponent("today-\(name).png"))
            try render(OnboardingView(model: model), size: NSSize(width: 650, height: 705), scheme: scheme, appearance: appearance, to: directory.appendingPathComponent("onboarding-\(name).png"))
            try render(MenuView(model: model, openPage: { _ in }, close: {}, quit: {}).fixedSize(), size: NSSize(width: 368, height: 480), scheme: scheme, appearance: appearance, to: directory.appendingPathComponent("menu-\(name).png"), fitContent: true)
            try render(BreakPromptView(kind: .short, start: {}, snooze: {}, skip: {}), size: NSSize(width: 356, height: 254), scheme: scheme, appearance: appearance, to: directory.appendingPathComponent("prompt-\(name).png"))
            for activity in MovementActivity.allCases {
                var movementSettings = settings
                movementSettings.movementActivity = activity
                try render(BreakPromptView(kind: .movement, settings: movementSettings, start: {}, snooze: {}, skip: {}),
                           size: NSSize(width: 356, height: 254), scheme: scheme, appearance: appearance,
                           to: directory.appendingPathComponent("movement-\(activity.rawValue)-\(name).png"))
            }
            for variant in BlinkCueVariant.allCases {
                try render(BlinkCueView(variant: variant), size: BlinkCueView.size, scheme: scheme, appearance: appearance, to: directory.appendingPathComponent("blink-\(variant)-\(name).png"))
                // NSAppearance alone doesn't set SwiftUI's read-only contrast
                // environment in an offscreen host. Exercise the real card's input.
                try render(BlinkCueCard(variant: variant, reduceMotion: true, contrast: .increased), size: BlinkCueView.size, scheme: scheme, appearance: appearance, to: directory.appendingPathComponent("blink-\(variant)-\(name)-increased-contrast.png"))
            }
        }
        try render(BreakCountdownView(state: OverlayState(), end: {}), size: NSSize(width: 440, height: 360), scheme: .dark, appearance: .darkAqua, to: directory.appendingPathComponent("countdown-dark.png"))
        let movement = OverlayState()
        movement.kind = .movement
        movement.settings = settings
        movement.remaining = 120
        try render(BreakCountdownView(state: movement, end: {}), size: NSSize(width: 440, height: 360), scheme: .dark, appearance: .darkAqua,
                   to: directory.appendingPathComponent("movement-countdown-dark.png"))
        movement.settings.completionSoundEnabled = false
        try render(BreakCountdownView(state: movement, end: {}), size: NSSize(width: 440, height: 360), scheme: .dark, appearance: .darkAqua,
                   to: directory.appendingPathComponent("movement-countdown-silent-dark.png"))
        model.stop()
    }

    @MainActor
    private func render<V: View>(_ view: V, size: NSSize, scheme: ColorScheme, appearance: NSAppearance.Name, to file: URL, fitContent: Bool = false) throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
        window.contentView = hosting
        hosting.setFrameSize(size)
        hosting.layoutSubtreeIfNeeded()
        if fitContent {
            let fittingSize = hosting.fittingSize
            window.setContentSize(fittingSize)
            hosting.setFrameSize(fittingSize)
            hosting.layoutSubtreeIfNeeded()
        }
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: file)
        window.close()
    }
}
