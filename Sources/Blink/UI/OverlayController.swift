import AppKit
import BlinkCore
import QuartzCore
import SwiftUI

@MainActor
final class OverlayState: ObservableObject {
    @Published var kind: BreakKind = .short
    @Published var remaining: TimeInterval = 20
    @Published var duration: TimeInterval = 20
    @Published var isPreview = false
    @Published var settings = AppSettings()
}

final class ReminderPanel: NSPanel {
    override var canBecomeKey: Bool { !ignoresMouseEvents }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayController {
    var onStart: ((BreakKind) -> Void)?
    var onSnooze: (() -> Void)?
    var onSkip: (() -> Void)?
    var onEnd: (() -> Void)?
    #if BLINK_ANIMATION_PROBE
    // Read-only observation in the standalone probe; absent from app builds.
    var onBlinkCleanup: ((String, NSPanel) -> Void)?
    #endif
    private var prompt: NSPanel?
    private var promptKind: BreakKind?
    private var promptSettings: AppSettings?
    private var dimmers: [NSPanel] = []
    private var breakPanels: [NSPanel] = []
    private var blinkPanel: NSPanel?
    private var blinkDismiss: Timer?
    private var blinkIsPreview = false
    private var blinkVariants = BlinkCueSequence()
    private var previewTimer: Timer?
    private let state = OverlayState()
    private var showingBreak = false

    var isPreviewing: Bool { (state.isPreview && showingBreak) || blinkIsPreview }

    func showPrompt(_ kind: BreakKind, settings: AppSettings = AppSettings()) {
        guard !isPreviewing else { return }
        guard prompt == nil || promptKind != kind || promptSettings != settings else { return }
        dismissPrompt()
        dismissBlink()
        let panel = makePanel(size: NSSize(width: 356, height: 254))
        panel.contentView = NSHostingView(rootView: BreakPromptView(kind: kind, settings: settings,
            start: { [weak self] in self?.onStart?(kind) },
            snooze: { [weak self] in self?.onSnooze?() },
            skip: { [weak self] in self?.onSkip?() }))
        positionPrompt(panel)
        prompt = panel
        promptKind = kind
        promptSettings = settings
        panel.orderFrontRegardless()
    }

    func dismissPrompt() {
        prompt?.orderOut(nil)
        prompt = nil
        promptKind = nil
        promptSettings = nil
    }

    /// Keyboard access is explicit; scheduled prompts never become key on their own.
    func focusPrompt() { prompt?.makeKeyAndOrderFront(nil) }

    func showBreak(kind: BreakKind, remaining: TimeInterval, duration: TimeInterval, settings: AppSettings = AppSettings()) {
        if isPreviewing { endPreview() }
        state.kind = kind
        state.remaining = remaining
        state.duration = duration
        state.isPreview = false
        state.settings = settings
        // The existing panels observe state, so updating remaining above is the
        // countdown update path; window creation happens only on first show.
        guard !showingBreak else { return }
        showingBreak = true
        dismissPrompt()
        dismissBlink()
        createBreakWindows(focusControls: true)
    }

    func dismissBreak() {
        guard !isPreviewing else { return }
        removeBreakWindows()
        showingBreak = false
    }

    func previewBreak(_ kind: BreakKind, settings: AppSettings = AppSettings()) {
        guard !showingBreak else { return }
        dismissPrompt()
        dismissBlink()
        state.kind = kind
        state.settings = settings
        state.remaining = 5
        state.duration = 5
        state.isPreview = true
        showingBreak = true
        createBreakWindows(focusControls: true)
        previewTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.state.remaining -= 1
                if self.state.remaining <= 0 { self.endPreview() }
            }
        }
    }

    func endPreview() {
        dismissBlink()
        previewTimer?.invalidate()
        previewTimer = nil
        removeBreakWindows()
        showingBreak = false
        state.isPreview = false
    }

    func showBlink(isPreview: Bool = false) {
        guard !showingBreak, prompt == nil else { return }
        // Very short configured intervals must not keep restarting a visible cue.
        guard isPreview || blinkPanel == nil else { return }
        dismissBlink()
        blinkIsPreview = isPreview
        // Drawn only after the guards above, so discarded arrivals do not use up a variant.
        let variant = blinkVariants.next()
        let panel = makePanel(size: BlinkCueView.size)
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0
        panel.contentView = NSHostingView(rootView: BlinkCueView(variant: variant))
        let frame = pointerScreen()?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        panel.setFrameOrigin(NSPoint(x: frame.maxX - panel.frame.width - 24, y: frame.maxY - panel.frame.height - 24))
        blinkPanel = panel
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = BlinkCueTiming.fadeIn
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 1
        }
        let timer = Timer(timeInterval: BlinkCueTiming.fadeOutStart, repeats: false) { [weak self, weak panel] _ in
            MainActor.assumeIsolated {
                guard let self, let panel, self.blinkPanel === panel else { return }
                self.fadeOutBlink(panel)
            }
        }
        blinkDismiss = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func fadeOutBlink(_ panel: NSPanel) {
        // Keep a bounded cleanup path even if AppKit delays its completion
        // callback. Anchor to the actual fade start, so a delayed timer cannot
        // cut the fade short. Normal completion invalidates this backstop.
        let backstop = Timer(timeInterval: BlinkCueTiming.fadeOut + 0.12, repeats: false) { [weak self, weak panel] _ in
            MainActor.assumeIsolated {
                guard let self, let panel, self.blinkPanel === panel else { return }
                self.dismissBlink()
                #if BLINK_ANIMATION_PROBE
                self.onBlinkCleanup?("backstop", panel)
                #endif
            }
        }
        blinkDismiss = backstop
        RunLoop.main.add(backstop, forMode: .common)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = BlinkCueTiming.fadeOut
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            MainActor.assumeIsolated {
                // A cancelled fade must never dismiss a newer cue or preview.
                guard let self, let panel, self.blinkPanel === panel else { return }
                self.dismissBlink()
                #if BLINK_ANIMATION_PROBE
                self.onBlinkCleanup?("completion", panel)
                #endif
            }
        }
    }

    func dismissBlink() {
        blinkIsPreview = false
        blinkDismiss?.invalidate()
        blinkDismiss = nil
        blinkPanel?.orderOut(nil)
        blinkPanel = nil
    }

    func displaysChanged() {
        dismissBlink()
        if showingBreak {
            removeBreakWindows()
            createBreakWindows(focusControls: false)
        }
        if let prompt { positionPrompt(prompt) }
    }

    func hideAll() {
        endPreview()
        dismissPrompt()
        dismissBlink()
    }

    private func createBreakWindows(focusControls: Bool) {
        for screen in NSScreen.screens {
            let dimmer = makePanel(size: screen.frame.size)
            dimmer.setFrame(screen.frame, display: false)
            dimmer.backgroundColor = NSColor.black.withAlphaComponent(0.42)
            dimmer.ignoresMouseEvents = true
            dimmer.hasShadow = false
            dimmer.orderFrontRegardless()
            dimmers.append(dimmer)

            let panel = makePanel(size: NSSize(width: 440, height: 360))
            panel.level = NSWindow.Level(rawValue: dimmer.level.rawValue + 1)
            panel.contentView = NSHostingView(rootView: BreakCountdownView(state: state) { [weak self] in
                guard let self else { return }
                if self.isPreviewing { self.endPreview() } else { self.onEnd?() }
            }.environment(\.colorScheme, .dark))
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 220, y: screen.visibleFrame.midY - 170))
            panel.orderFrontRegardless()
            breakPanels.append(panel)
        }
        if focusControls {
            let index = NSScreen.screens.firstIndex(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? 0
            if breakPanels.indices.contains(index) { breakPanels[index].makeKey() }
        }
    }

    private func removeBreakWindows() {
        (dimmers + breakPanels).forEach { $0.orderOut(nil) }
        dimmers.removeAll()
        breakPanels.removeAll()
    }

    private func makePanel(size: NSSize) -> NSPanel {
        let panel = ReminderPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications, .ignoresCycle]
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        return panel
    }

    private func pointerScreen() -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func positionPrompt(_ panel: NSPanel) {
        guard let frame = pointerScreen()?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: frame.maxX - panel.frame.width - 22, y: frame.maxY - panel.frame.height - 22))
    }
}

struct BreakPromptView: View {
    let kind: BreakKind
    var settings = AppSettings()
    let start: () -> Void
    let snooze: () -> Void
    let skip: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                if kind == .movement {
                    Image(systemName: kind.symbol).font(.system(size: 21, weight: .medium))
                        .foregroundStyle(BlinkStyle.accent).frame(width: 38, height: 38)
                        .background(BlinkStyle.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
                        .accessibilityHidden(true)
                } else { EyeMark(size: 38) }
                VStack(alignment: .leading, spacing: 4) {
                    SectionEyebrow(text: kind == .movement ? "Movement break" : "A moment for your eyes")
                    Text(kind == .movement ? settings.movementActivity.promptTitle : kind == .short ? "Let your gaze wander." : "Time for a longer pause.")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                }
            }
            Text(kind == .movement ? "Step away from your screen. Go at your own pace." : kind == .short ? "Look beyond your screen, about 20 feet / 6 metres away." : "Step away from screens. Move, stretch, and give your eyes a rest.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button(kind == .movement ? settings.movementStartTitle : "Start break", action: start)
                .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.return, modifiers: [])
            HStack(spacing: 10) {
                Button(action: snooze) { Text("Snooze 5 minutes").actionTarget(expands: true) }
                Button(action: skip) { Text("Skip").actionTarget(expands: true) }
                    .keyboardShortcut(.escape, modifiers: [])
            }.buttonStyle(.bordered).controlSize(.large).font(.system(size: 12))
        }
        .padding(20).frame(width: 356, height: 254)
        .background(BlinkStyle.canvas, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.primary.opacity(0.08)))
        .tint(BlinkStyle.accent)
    }
}

struct BreakCountdownView: View {
    @ObservedObject var state: OverlayState
    let end: () -> Void
    var body: some View {
        VStack(spacing: 17) {
            SectionEyebrow(text: state.isPreview ? "Reminder preview" : state.kind == .movement ? "Your time to move" : "Your time to rest")
            Image(systemName: state.kind.symbol)
                .font(.system(size: 33, weight: .light)).foregroundStyle(BlinkStyle.accent).accessibilityHidden(true)
            Text(state.kind == .movement ? "Make room to move." : state.kind == .short ? "Look a little further." : "Step away. Take your time.")
                .font(.system(size: 25, weight: .medium, design: .rounded))
            Text(state.kind == .movement ? state.settings.movementActivity.instruction : state.kind == .short ? "Rest your gaze about 20 feet / 6 metres away.\nBlink fully and deliberately." : "Leave your screens behind for a while.\nA walk, some water, a different view.")
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            if state.kind == .movement {
                Text(state.isPreview ? "Preview closes automatically." : state.settings.completionSoundEnabled
                     ? "Keep your eyes off the screen. A chime plays when time is up."
                     : "Keep your eyes off the screen. The screen returns when time is up.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(clockText(state.remaining)).font(.system(size: state.kind == .movement ? 24 : 40, weight: .light, design: .rounded)).monospacedDigit()
                .accessibilityLabel("Time remaining").accessibilityValue(clockText(state.remaining))
            Button(action: end) { Text(state.isPreview ? "Close preview" : "End break").actionTarget() }
                .buttonStyle(.bordered).controlSize(.large).keyboardShortcut(.escape, modifiers: [])
        }
        .padding(28).frame(width: 440, height: 360)
        .background(Color(red: 0.075, green: 0.12, blue: 0.105).opacity(0.97), in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.10)))
        .tint(BlinkStyle.accent)
    }
}
