import AppKit
import BlinkCore
import SwiftUI
import Testing
@testable import Blink

/// Opt-in native pointer checks. Events go only to this test process's windows,
/// placed outside the desktop. No global events, permissions, or user state.
@Suite("Native hit targets", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["BLINK_HIT_CHECKS"] == "1"))
struct HitTargetTests {
    @Test("Reminder padding activates the intended button and gaps do not", arguments: [BreakKind.short, .movement, .long])
    @MainActor
    func reminderActions(kind: BreakKind) throws {
        var actions = [0, 0, 0]
        let window = host(BreakPromptView(kind: kind,
            start: { actions[0] += 1 }, snooze: { actions[1] += 1 }, skip: { actions[2] += 1 }))
        defer { window.close() }
        let view = try #require(window.contentView)
        let targets = try buttonFrames(in: view, expected: 3)
        for (index, target) in targets.enumerated() {
            for point in [NSPoint(x: target.minX + 4, y: target.midY),
                          NSPoint(x: target.maxX - 4, y: target.midY),
                          NSPoint(x: target.midX, y: target.maxY - 4)] {
                let before = actions
                click(point, in: window)
                for action in actions.indices {
                    #expect(actions[action] == before[action] + (action == index ? 1 : 0))
                }
            }
        }
        let before = actions
        click(NSPoint(x: (targets[1].maxX + targets[2].minX) / 2, y: targets[1].midY), in: window)
        #expect(actions == before)

        // Exercise the native shortcut route without sending system-wide key events.
        for (key, code, action) in [("\r", UInt16(36), 0), ("\u{1b}", UInt16(53), 2)] {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: code))
            let previous = actions[action]
            #expect(window.performKeyEquivalent(with: event))
            #expect(actions[action] == previous + 1)
        }
    }

    @Test("Menu buttons have generous targets and footer whitespace is clickable")
    @MainActor
    func menuActions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BlinkHitChecks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StateStore(directory: directory)
        var engine = ReminderEngine(now: Date())
        engine.completeOnboarding(now: Date())
        try store.save(engine.state)
        let model = AppModel(store: store)
        defer { model.stop() }
        var pages: [AppPage] = []
        var quits = 0
        let window = host(MenuView(model: model, openPage: { pages.append($0) }, close: {}, quit: { quits += 1 }).fixedSize())
        defer { window.close() }
        let view = try #require(window.contentView)
        let targets = try buttonFrames(in: view, expected: 11)
        for target in targets.suffix(4) {
            click(NSPoint(x: target.minX + 4, y: target.midY), in: window)
        }
        #expect(pages == [.feedback, .today, .settings])
        #expect(quits == 1)
    }

    @Test("Sidebar rows activate from empty space beyond their text")
    @MainActor
    func sidebarActions() throws {
        var selection = AppPage.settings
        let window = host(SidebarNavigation(selection: Binding(get: { selection }, set: { selection = $0 }))
            .padding(17).frame(width: 170))
        defer { window.close() }
        let targets = try buttonFrames(in: #require(window.contentView), expected: 4)
        for (index, target) in targets.enumerated() {
            // The far-right part of every row is empty, including "Screen setup".
            click(NSPoint(x: target.maxX - 4, y: target.midY), in: window)
            #expect(selection == AppPage.allCases[index])
        }
    }

    @Test("Feedback keeps Gmail and copy available after the email handler accepts a URL")
    @MainActor
    func feedbackActions() throws {
        var opened: [String] = []
        let window = host(FeedbackView().padding(28).frame(width: 628, height: 600)
            .environment(\.openURL, OpenURLAction { url in
                opened.append(url.absoluteString)
                return .handled
            }))
        defer { window.close() }
        let targets = try buttonFrames(in: #require(window.contentView), expected: 3)
        for target in targets.prefix(2) {
            click(NSPoint(x: target.minX + 4, y: target.midY), in: window)
        }
        #expect(opened == ["mailto:blink@wellkernel.com?subject=Blink%20feedback",
                           "https://mail.google.com/mail/?view=cm&fs=1&to=blink@wellkernel.com&su=Blink%20feedback"])

        let pasteboard = NSPasteboard.general
        let savedItems = (pasteboard.pasteboardItems ?? []).map { item in
            let saved = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { saved.setData(data, forType: type) }
            }
            return saved
        }
        defer {
            pasteboard.clearContents()
            if !savedItems.isEmpty { pasteboard.writeObjects(savedItems) }
        }
        let copy = try #require(targets.last)
        click(NSPoint(x: copy.minX + 4, y: copy.midY), in: window)
        #expect(pasteboard.string(forType: .string) == "blink@wellkernel.com")
    }

    @Test("Guide links have native button targets and open only their intended URLs")
    @MainActor
    func guideLinks() throws {
        var opened: [String] = []
        let window = host(ScreenGuide().padding(28).frame(width: 650)
            .environment(\.openURL, OpenURLAction { url in
                opened.append(url.absoluteString)
                return .handled
            }))
        defer { window.close() }
        let targets = try buttonFrames(in: #require(window.contentView), expected: 2)
        for target in targets {
            click(NSPoint(x: target.minX + 4, y: target.midY), in: window)
        }
        #expect(opened == ["https://www.aoa.org/healthy-eyes/eye-and-vision-conditions/computer-vision-syndrome",
                           "https://pubmed.ncbi.nlm.nih.gov/24413278/"])
    }

    @MainActor
    private func host<V: View>(_ view: V) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 400, height: 500),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        window.setContentSize(hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        return window
    }

    @MainActor
    private func buttonFrames(in view: NSView, expected: Int) throws -> [NSRect] {
        // SwiftUI's native focus-ring views expose each control's laid-out bounds.
        // This diagnostic is deliberately macOS-specific; fail if that changes.
        func descendants(_ root: NSView) -> [NSView] {
            root.subviews.flatMap { [$0] + descendants($0) }
        }
        let controls = descendants(view).filter { String(describing: type(of: $0)) == "_FocusRingView" }
        let unsorted: [NSRect] = controls.map { $0.convert($0.bounds, to: view) }
        let frames = unsorted.sorted { (lhs: NSRect, rhs: NSRect) -> Bool in
            if abs(lhs.minY - rhs.minY) > 1 { return lhs.minY < rhs.minY }
            return lhs.minX < rhs.minX
        }
        try #require(frames.count == expected)
        for frame in frames {
            #expect(frame.width >= 43.5 && frame.height >= 43.5)
            #expect(view.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame))
        }
        print("Native button frames:", frames)
        return frames
    }

    @MainActor
    private func click(_ point: NSPoint, in window: NSWindow) {
        let location = window.contentView!.convert(point, to: nil)
        let time = ProcessInfo.processInfo.systemUptime
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: time,
                                     windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [], timestamp: time + 0.01,
                                   windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!
        window.sendEvent(down)
        window.sendEvent(up)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
}
