import AppKit
import BlinkCore
import Combine
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: EngineSnapshot
    @Published var errorMessage: String?
    @Published private(set) var launchAtLogin = false
    @Published private(set) var loginNeedsApproval = false
    @Published private(set) var needsStorageReset = false
    @Published var globalShortcutAvailable = false
    @Published var globalShortcutDescription = ShortcutDescription(key: "B")
    var onChange: (() -> Void)?
    var hasVisibleCountdown: (() -> Bool)?
    var onOpenPage: ((AppPage) -> Void)?
    var onOnboardingFinished: (() -> Void)?
    let overlays = OverlayController()
    private let monitor = SystemMonitor()
    private let store: StateStore
    private let announcements: ReminderAnnouncer
    private var engine: ReminderEngine
    private var timer: Timer?
    private let clock = ContinuousClock()
    private let suspendingClock = SuspendingClock()
    private let origin: ContinuousClock.Instant
    private let suspendingOrigin: SuspendingClock.Instant
    private var availability: AvailabilityClock
    private var lastPersist: TimeInterval = 0
    private var unavailable = false

    init(store: StateStore = StateStore(), announcements: ReminderAnnouncer = ReminderAnnouncer()) {
        self.store = store
        self.announcements = announcements
        let now = Date()
        var loadError: String?
        let state: EngineState
        do { state = try store.load() ?? EngineState(now: now) }
        catch {
            state = EngineState(now: now)
            loadError = "Blink couldn't read its saved settings. Temporary defaults are active, and the saved file will remain untouched. You can reset the unreadable saved data in Settings. \(error.localizedDescription)"
        }
        engine = ReminderEngine(state: state, now: now, calendar: .autoupdatingCurrent)
        snapshot = engine.snapshot
        origin = clock.now
        suspendingOrigin = suspendingClock.now
        unavailable = monitor.isUnavailable
        availability = AvailabilityClock(time: 0, suspendingTime: 0, isUnavailable: unavailable)
        errorMessage = loadError
        needsStorageReset = loadError != nil
        configureCallbacks()
        refreshLoginStatus()
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        publish(persist: true)
    }

    func stop() {
        tick()
        timer?.invalidate()
        timer = nil
        persist()
        monitor.stop()
        overlays.hideAll()
    }

    func tick(forceInterface: Bool = false) {
        let now = Date()
        let time = seconds(origin.duration(to: clock.now))
        unavailable = monitor.isUnavailable
        let suspendingTime = seconds(suspendingOrigin.duration(to: suspendingClock.now))
        let interval = availability.sample(time: time, suspendingTime: suspendingTime, isUnavailable: unavailable)
        let effects = engine.tick(now: now, elapsed: interval.elapsed, unavailableElapsed: interval.unavailableElapsed,
                                  idleSeconds: monitor.idleSeconds, isUnavailable: unavailable)
        publish(persist: time - lastPersist >= 15 || !effects.isEmpty, forceInterface: forceInterface)
        if time - lastPersist >= 15 { lastPersist = time }
        for effect in effects {
            switch effect {
            case .blink: overlays.showBlink()
            case .breakCompleted(let kind):
                announcements.completed(kind, unavailable: unavailable)
                if snapshot.settings.completionSoundEnabled && !unavailable {
                    NSSound(named: "Glass")?.play()
                }
            }
        }
    }

    func startBreak(_ kind: BreakKind) {
        tick()
        overlays.endPreview()
        engine.startBreak(kind, now: Date())
        publish(persist: true)
    }

    func snooze() { tick(); engine.snooze(now: Date()); publish(persist: true) }
    func skip() { tick(); engine.skip(now: Date()); publish(persist: true) }
    func endBreak() { tick(); engine.endBreakEarly(now: Date()); publish(persist: true) }

    func quiet(minutes: Int?) {
        tick()
        overlays.endPreview()
        engine.setQuiet(until: minutes.map { Date().addingTimeInterval(Double($0) * 60) }, now: Date())
        publish(persist: true)
    }

    func resume() { tick(); engine.resume(now: Date()); publish(persist: true) }

    @discardableResult
    func saveSettings(_ settings: AppSettings) -> Bool {
        tick()
        do {
            try engine.updateSettings(settings, now: Date())
            publish(persist: true)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func finishOnboarding() {
        tick()
        engine.completeOnboarding(now: Date())
        publish(persist: true)
        onOnboardingFinished?()
    }

    func preview(_ kind: BreakKind, settings: AppSettings? = nil) {
        guard snapshot.activeBreak == nil, !unavailable else { return }
        overlays.previewBreak(kind, settings: settings ?? snapshot.settings)
    }

    func previewBlink() {
        guard engine.snapshot.activeBreak == nil, engine.snapshot.pendingBreak == nil, !unavailable else { return }
        overlays.showBlink(isPreview: true)
    }

    func resetUnreadableStorage() {
        guard needsStorageReset else { return }
        // This is an explicit user action in Settings; startup never overwrites
        // a malformed or newer-version file with temporary defaults.
        do {
            try store.save(engine.state)
            needsStorageReset = false
        } catch { errorMessage = "Blink couldn't reset its saved data. \(error.localizedDescription)" }
    }

    func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled || status == .requiresApproval
        loginNeedsApproval = status == .requiresApproval
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { errorMessage = "Couldn't change launch at login. \(error.localizedDescription)" }
        refreshLoginStatus()
    }

    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }

    private func configureCallbacks() {
        monitor.onChange = { [weak self] in self?.tick() }
        monitor.onDisplaysChange = { [weak self] in self?.overlays.displaysChanged() }
        overlays.onStart = { [weak self] in self?.startBreak($0) }
        overlays.onSnooze = { [weak self] in self?.snooze() }
        overlays.onSkip = { [weak self] in self?.skip() }
        overlays.onEnd = { [weak self] in self?.endBreak() }
    }

    private func publish(persist shouldPersist: Bool, forceInterface: Bool = false) {
        let current = engine.snapshot
        let semanticChange = snapshot.settings != current.settings || snapshot.summary != current.summary
            || snapshot.status != current.status || snapshot.pendingBreak != current.pendingBreak
            || snapshot.activeBreak?.kind != current.activeBreak?.kind || snapshot.isQuiet != current.isQuiet
            || snapshot.quietUntil != current.quietUntil
        let minuteChange = ceil(snapshot.shortRemaining / 60) != ceil(current.shortRemaining / 60)
            || ceil(snapshot.longRemaining / 60) != ceil(current.longRemaining / 60)
            || ceil(snapshot.movementRemaining / 60) != ceil(current.movementRemaining / 60)
        // Do not invalidate hidden SwiftUI trees every second. Only an open menu
        // needs live schedule values; active overlay countdowns have their own model.
        if forceInterface || semanticChange || minuteChange || hasVisibleCountdown?() == true {
            snapshot = current
            onChange?()
        }
        if unavailable {
            overlays.hideAll()
        } else if overlays.isPreviewing {
            // A deliberately requested preview is independent of timer/quiet state.
        } else if let active = current.activeBreak {
            // An explicitly started break remains visible during quiet mode;
            // the user's quiet period continues after the manual break finishes.
            overlays.showBreak(kind: active.kind, remaining: active.remaining,
                               duration: current.settings.duration(for: active.kind), settings: current.settings)
        } else if current.status == .idle || current.status == .onboarding || current.isQuiet {
            overlays.hideAll()
        } else {
            overlays.dismissBreak()
            if let pending = current.pendingBreak { overlays.showPrompt(pending, settings: current.settings) }
            else { overlays.dismissPrompt() }
        }
        let openHint = globalShortcutAvailable
            ? "Press \(globalShortcutDescription.spoken) to open Blink."
            : "Open Blink from the menu bar."
        announcements.update(current, unavailable: unavailable, previewing: overlays.isPreviewing, openHint: openHint)
        if shouldPersist { persist() }
    }

    private func persist() {
        guard !needsStorageReset else { return }
        do { try store.save(engine.state) }
        catch { errorMessage = "Blink couldn't save its settings. \(error.localizedDescription)" }
    }
}
