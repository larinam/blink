import AppKit
import BlinkCore
import CoreGraphics
import Foundation

@main
struct BlinkAnimationCheck {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let check = AnimationCheck()
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { _ in
            MainActor.assumeIsolated { check.start() }
        }
        app.run()
    }
}

@MainActor
private final class AnimationCheck {
    private let overlays = OverlayController()
    private var baseline: Set<ObjectIdentifier> = []
    private var keyWindow: NSWindow?
    private var original: NSWindow?
    private var replacement: NSWindow?
    private var failures: [String] = []
    private var samples: [[String: Double]] = []
    private var environmentSamples: [[String: Any]] = []
    private var cleanupEvents: [[String: Any]] = []
    private var cueNames: [ObjectIdentifier: String] = [:]
    private var startTime = Date()
    private var steps: [(Double, () -> Void)] = []
    private var timer: Timer?

    private var panels: [NSWindow] {
        NSApplication.shared.windows.filter {
            $0 is ReminderPanel && $0.isVisible && !baseline.contains(ObjectIdentifier($0))
        }
    }

    func start() {
        startTime = Date()
        requireEnvironment(at: "start")
        baseline = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
        keyWindow = NSApplication.shared.keyWindow
        overlays.onBlinkCleanup = { [weak self] path, panel in
            guard let self else { return }
            self.cleanupEvents.append([
                "path": path,
                "cue": self.cueNames[ObjectIdentifier(panel)] ?? "unknown",
                "seconds": Date().timeIntervalSince(self.startTime),
                "panel_visible_after_cleanup": panel.isVisible,
                "alpha": panel.alphaValue
            ])
            self.requireEnvironment(at: "cleanup: \(path)")
        }
        overlays.showBlink(isPreview: true)
        original = panels.first
        if let original { cueNames[ObjectIdentifier(original)] = "initial" }
        expect(panels.count == 1, "one cue panel")
        expect(original?.alphaValue == 0, "starts transparent")
        samples.append(["seconds": Date().timeIntervalSince(startTime), "alpha": original?.alphaValue ?? -1])
        let frame = original?.frame
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        expect(screen?.visibleFrame.contains(frame ?? .zero) == true, "pointer display")
        for time in [0.1, 0.18, 0.35, 0.65, 1.2, 2.0, 2.80, 2.90] {
            steps.append((time, { [self] in
                requireEnvironment(at: "opacity sample: \(time)")
                let alpha = original?.alphaValue ?? -1
                samples.append(["seconds": Date().timeIntervalSince(startTime), "alpha": alpha])
                expect(original?.frame == frame, "stationary card")
                expect(original?.ignoresMouseEvents == true && original?.canBecomeKey == false, "click-through, non-key cue")
                expect(NSApplication.shared.keyWindow === keyWindow, "focus preserved")
                if time == 0.1 || time == 2.8 { expect(alpha > 0 && alpha < 1, "interpolated fade at \(time)") }
                if time == 0.18 { expect(alpha > samples[samples.count - 2]["alpha"]! && alpha < 1, "fade increases") }
                if time == 0.35 || time == 2.0 { expect(alpha == 1, "opaque hold at \(time)") }
                if time == 2.9 { expect(alpha >= 0 && alpha < samples[samples.count - 2]["alpha"]!, "fade decreases") }
                if time == 0.35 || time == 0.65 || time == 1.2 { captureCard(name: "cue-\(time)") }
            }))
        }
        steps.append((3.3, { [self] in
            requireEnvironment(at: "initial cue finished")
            expect(original?.isVisible == false && panels.isEmpty && !overlays.isPreviewing, "fade completion removes panel and preview state")
            let initialEvents = cleanupEvents.filter { $0["cue"] as? String == "initial" }
            expect(initialEvents.count == 1 && initialEvents.first?["path"] as? String == "completion", "ordinary cleanup uses animation completion, not the backstop")
            overlays.showBlink()
            original = panels.first
            if let original { cueNames[ObjectIdentifier(original)] = "scheduled" }
            overlays.showBlink()
            expect(panels.count == 1 && panels.first === original, "scheduled arrivals do not restart a cue")
        }))
        steps.append((6.12, { [self] in
            requireEnvironment(at: "replace during fade")
            expect((original?.alphaValue ?? 1) < 1, "replacement occurs during fade")
            overlays.showBlink(isPreview: true)
            replacement = panels.first
            if let replacement { cueNames[ObjectIdentifier(replacement)] = "replacement" }
            expect(replacement != nil && replacement !== original && original?.isVisible == false, "explicit preview replaces immediately")
        }))
        steps.append((6.6, { [self] in
            requireEnvironment(at: "final cancellation checks")
            expect(replacement?.isVisible == true && overlays.isPreviewing && panels.count == 1, "old completion cannot remove replacement")
            expect(!cleanupEvents.contains { $0["cue"] as? String == "scheduled" }, "cancelled cue never reports stale cleanup")
            overlays.hideAll()
            expect(panels.isEmpty && !overlays.isPreviewing, "hideAll clears cue immediately")
            overlays.showBlink()
            let cue = panels.first
            overlays.showPrompt(.short)
            expect(cue?.isVisible == false && panels.count == 1, "prompt cancels cue")
            let prompt = panels.first
            overlays.showBlink()
            expect(panels.first === prompt && panels.count == 1, "pending prompt suppresses cue")
            overlays.hideAll()
            overlays.showBlink()
            let displayCue = panels.first
            overlays.displaysChanged()
            expect(displayCue?.isVisible == false && panels.isEmpty, "display change cancels cue")
            overlays.showBlink()
            let breakCue = panels.first
            overlays.showBreak(kind: .short, remaining: 20, duration: 20)
            expect(breakCue?.isVisible == false && panels.count == NSScreen.screens.count * 2, "break cancels cue")
            overlays.hideAll()
            expect(panels.isEmpty, "final cleanup")
            finish()
        }))
        timer = Timer.scheduledTimer(withTimeInterval: 0.005, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let elapsed = Date().timeIntervalSince(self.startTime)
                while let step = self.steps.first, elapsed >= step.0 {
                    self.steps.removeFirst()
                    step.1()
                }
                if elapsed > 12 { self.expect(false, "probe deadline"); self.finish() }
            }
        }
    }

    private func expect(_ condition: Bool, _ label: String) {
        if !condition { failures.append(label) }
    }

    private func requireEnvironment(at label: String) {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let locked = session?["CGSSessionScreenIsLocked"] as? Bool ?? false
        let onConsole = session?["kCGSSessionOnConsoleKey"] as? Bool ?? false
        var displays: [[String: Any]] = []
        var awake = !NSScreen.screens.isEmpty
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                displays.append(["id": NSNull(), "asleep": NSNull()])
                awake = false
                continue
            }
            let asleep = CGDisplayIsAsleep(id) != 0
            displays.append(["id": id, "asleep": asleep])
            if asleep { awake = false }
        }
        let ready = session != nil && !locked && onConsole && awake
        environmentSamples.append([
            "at": label, "seconds": Date().timeIntervalSince(startTime),
            "utc": ISO8601DateFormatter().string(from: Date()),
            "session_readable": session != nil,
            "lock_flag_present": session?["CGSSessionScreenIsLocked"] != nil,
            "locked": session == nil ? NSNull() : locked as Any,
            "on_console": onConsole,
            "displays": displays, "ready": ready
        ])
        guard ready else {
            expect(false, "Native animation check requires an unlocked console session and awake displays (\(label))")
            finish()
        }
    }

    private func captureCard(name: String) {
        guard let path = ProcessInfo.processInfo.environment["BLINK_ANIMATION_RENDER_DIR"],
              let view = original?.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        do {
            let directory = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name + ".png"))
        } catch { failures.append("capture: \(error)") }
    }

    private func finish() -> Never {
        timer?.invalidate()
        overlays.hideAll()
        let report: [String: Any] = ["passed": failures.isEmpty, "failures": failures,
            "alpha_samples": samples, "displays": NSScreen.screens.count,
            "cleanup_events": cleanupEvents, "environment_samples": environmentSamples]
        let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        exit(failures.isEmpty ? 0 : 1)
    }
}
