import AppKit
import BlinkCore
import SwiftUI
import Testing
@testable import Blink

@Suite("Native blink animation", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["BLINK_ANIMATION_CHECKS"] == "1"))
struct BlinkAnimationTests {
    @Test("A delayed animation completion cannot block later scheduled cues")
    @MainActor
    func boundedCleanup() throws {
        let baseline = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
        let overlays = OverlayController()
        defer { overlays.hideAll() }
        func panels() -> [NSWindow] {
            NSApplication.shared.windows.filter {
                $0 is ReminderPanel && $0.isVisible && !baseline.contains(ObjectIdentifier($0))
            }
        }
        overlays.showBlink(isPreview: true)
        let original = try #require(panels().first)
        // Deliberately hold this main-queue invocation in a nested run loop.
        // Native timers run, while a queued animation completion may be delayed.
        RunLoop.main.run(until: Date().addingTimeInterval(3.3))
        #expect(!original.isVisible && !overlays.isPreviewing && panels().isEmpty)
        overlays.showBlink()
        #expect(panels().count == 1 && panels().first !== original)
    }

    @Test("Eye fully closes, reopens, and stays open at the end")
    @MainActor
    func finiteBlink() throws {
        let window = eyeWindow(AnimatedBlinkEye(reduceMotion: false))
        defer { window.close() }
        let view = try #require(window.contentView)
        let start = Date()
        var heights: [(Double, Double)] = []
        for time in [0.10, 0.60, 0.65, 0.70, 0.75, 0.90, 1.20, 2.0] {
            RunLoop.main.run(until: start.addingTimeInterval(time))
            let bitmap = try capture(view, name: "eye-\(time)")
            heights.append((time, brightHeight(bitmap, viewHeight: view.bounds.height)))
        }
        #expect(heights[0].1 > 15)
        #expect(heights[1...4].map(\.1).min()! < 4)
        #expect(abs(heights[6].1 - heights[0].1) < 1)
        #expect(abs(heights[7].1 - heights[0].1) < 1)
        print("Eye aperture heights in points:", heights)
    }

    @Test("Each variant closes fully at every hold and ends open before the fade", arguments: BlinkCueVariant.allCases)
    @MainActor
    func variantMotion(_ variant: BlinkCueVariant) throws {
        // Closed holds as [start, end] seconds from presentation, derived from the variant's own steps.
        var holds: [(Double, Double)] = []
        var elapsed = 0.0
        var previous = 1.0
        for step in variant.steps {
            if previous == 0 && step.openness == 0 { holds.append((elapsed, elapsed + step.duration)) }
            elapsed += step.duration
            previous = step.openness
        }
        let window = eyeWindow(AnimatedBlinkEye(reduceMotion: false, steps: variant.steps))
        defer { window.close() }
        let view = try #require(window.contentView)
        let start = Date()
        func height(at time: Double, _ name: String) throws -> Double {
            RunLoop.main.run(until: start.addingTimeInterval(time))
            return brightHeight(try capture(view, name: "\(variant)-\(name)"), viewHeight: view.bounds.height)
        }
        let open = try height(at: 0.1, "open")
        // Several samples per hold tolerate presentation latency; the minimum must be shut.
        let closed = try holds.enumerated().map { index, hold in
            try stride(from: hold.0, through: hold.1 + 0.05, by: (hold.1 + 0.05 - hold.0) / 3)
                .map { try height(at: $0, "hold\(index)-\($0)") }.min()!
        }
        let ended = try height(at: elapsed + 0.15, "ended")
        let beforeFade = try height(at: BlinkCueTiming.fadeOutStart - 0.05, "before-fade")
        #expect(open > 15)
        #expect(!closed.isEmpty && closed.allSatisfy { $0 < 4 })
        #expect(abs(ended - open) < 1 && abs(beforeFade - open) < 1)
        print("\(variant) aperture: open \(open), holds \(closed), ended \(ended), before fade \(beforeFade)")
    }

    @Test("Reduce Motion keeps the eye static, including a live change")
    @MainActor
    func reduceMotion() throws {
        let settings = MotionSettings()
        let window = eyeWindow(MotionHarness(settings: settings))
        defer { window.close() }
        let view = try #require(window.contentView)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let open = brightHeight(try capture(view, name: "motion-open"), viewHeight: view.bounds.height)
        RunLoop.main.run(until: Date().addingTimeInterval(0.45))
        settings.reduced = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        let reduced = brightHeight(try capture(view, name: "motion-reduced"), viewHeight: view.bounds.height)
        settings.reduced = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        let restored = brightHeight(try capture(view, name: "motion-restored"), viewHeight: view.bounds.height)
        #expect(open > 15 && abs(reduced - open) < 1 && abs(restored - open) < 1)

        let staticWindow = eyeWindow(AnimatedBlinkEye(reduceMotion: true))
        defer { staticWindow.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.7))
        let staticView = try #require(staticWindow.contentView)
        #expect(brightHeight(try capture(staticView, name: "motion-static"), viewHeight: staticView.bounds.height) > 15)
    }

    @MainActor
    private func eyeWindow<V: View>(_ view: V) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 58, height: 48),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view.foregroundStyle(.white).padding(10).background(.black))
        window.contentView?.layoutSubtreeIfNeeded()
        window.orderFrontRegardless()
        return window
    }

    @MainActor
    private func capture(_ view: NSView, name: String) throws -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let path = ProcessInfo.processInfo.environment["BLINK_ANIMATION_RENDER_DIR"] {
            let directory = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent(name + ".png"))
        }
        return bitmap
    }

    @MainActor
    private func brightHeight(_ bitmap: NSBitmapImageRep, viewHeight: CGFloat) -> Double {
        var first = bitmap.pixelsHigh
        var last = -1
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.redComponent > 0.7 && color.greenComponent > 0.7 && color.blueComponent > 0.7 {
                    first = min(first, y)
                    last = max(last, y)
                }
            }
        }
        return Double(max(0, last - first + 1)) * viewHeight / Double(bitmap.pixelsHigh)
    }
}

@MainActor
private final class MotionSettings: ObservableObject {
    @Published var reduced = false
}

private struct MotionHarness: View {
    @ObservedObject var settings: MotionSettings
    var body: some View { AnimatedBlinkEye(reduceMotion: settings.reduced) }
}
