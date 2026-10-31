import AppKit
import CoreGraphics

/// Observes availability and elapsed input inactivity only. It never installs an
/// event tap, reads key contents, or requests Input Monitoring permission.
@MainActor
final class SystemMonitor {
    var onChange: (() -> Void)?
    var onDisplaysChange: (() -> Void)?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var applicationObservers: [NSObjectProtocol] = []
    private var sleeping = false
    private var displaySleeping = false
    private var sessionInactive = false
    private var locked = false
    /// Uptime when a sleep or display-sleep flag was last set.
    private var sleepMarkedAt: TimeInterval?
    private let sessionInfo: () -> [String: Any]?
    private let inputIdle: () -> TimeInterval?
    private let uptime: () -> TimeInterval
    private let workspaceCenter: NotificationCenter

    init(sessionInfo: @escaping () -> [String: Any]? = {
        CGSessionCopyCurrentDictionary() as? [String: Any]
    }, inputIdle: @escaping () -> TimeInterval? = SystemMonitor.systemInputIdle,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.sessionInfo = sessionInfo
        self.inputIdle = inputIdle
        self.uptime = uptime
        self.workspaceCenter = workspaceCenter
        refreshSession()
        observeWorkspace(NSWorkspace.willSleepNotification) { $0.sleeping = true; $0.sleepMarkedAt = $0.uptime() }
        observeWorkspace(NSWorkspace.didWakeNotification) { $0.sleeping = false }
        observeWorkspace(NSWorkspace.screensDidSleepNotification) { $0.displaySleeping = true; $0.sleepMarkedAt = $0.uptime() }
        observeWorkspace(NSWorkspace.screensDidWakeNotification) { $0.displaySleeping = false }
        observeWorkspace(NSWorkspace.sessionDidResignActiveNotification) { $0.sessionInactive = true }
        observeWorkspace(NSWorkspace.sessionDidBecomeActiveNotification) { monitor in
            monitor.sessionInactive = false
            monitor.refreshSession()
        }
        // Screen lock has no dedicated NSWorkspace notification. Observe the
        // WindowServer distributed notifications and reconcile its session state.
        for (name, value) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            distributedObservers.append(DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(name), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.locked = value
                    self?.onChange?()
                }
            })
        }
        applicationObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onDisplaysChange?() }
        })
    }

    var isUnavailable: Bool {
        refreshSession()
        reconcileSleepWithInput()
        return sleeping || displaySleeping || sessionInactive || locked
    }

    /// Seconds since the last keyboard or pointer input; 0 when no input time is readable.
    var idleSeconds: TimeInterval { inputIdle() ?? 0 }

    /// The most recent valid input time, or nil when none can be read.
    nonisolated static func systemInputIdle() -> TimeInterval? {
        let events: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .leftMouseDragged, .rightMouseDragged]
        return events.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .filter { $0.isFinite && $0 >= 0 }
            .min()
    }

    func stop() {
        workspaceObservers.forEach { workspaceCenter.removeObserver($0) }
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        applicationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        workspaceObservers.removeAll()
        distributedObservers.removeAll()
        applicationObservers.removeAll()
    }

    private func observeWorkspace(_ name: Notification.Name, change: @escaping @MainActor (SystemMonitor) -> Void) {
        workspaceObservers.append(workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                change(self)
                self.onChange?()
            }
        })
    }

    /// A dropped wake notification would otherwise latch the sleep flags until the
    /// next sleep. Keyboard or pointer input after the latest flag shows that the
    /// user is back, so it clears both flags. Unreadable or invalid timing, or input
    /// from before the flag (such as the keystroke that slept the display), keeps them.
    private func reconcileSleepWithInput() {
        guard sleeping || displaySleeping, let sleepMarkedAt else { return }
        let sinceMark = uptime() - sleepMarkedAt
        guard sinceMark.isFinite, sinceMark >= 0,
              let idle = inputIdle(), idle.isFinite, idle >= 0,
              idle + Self.inputSkew < sinceMark else { return }
        sleeping = false
        displaySleeping = false
        self.sleepMarkedAt = nil
    }

    /// Tolerance for sampling skew between the input and uptime clocks.
    private static let inputSkew: TimeInterval = 1

    private func refreshSession() {
        guard let dictionary = sessionInfo() else { return }
        if let onConsole = dictionary[kCGSessionOnConsoleKey as String] as? Bool {
            sessionInactive = !onConsole
        }
        // WindowServer omits this flag for an unlocked session. Retaining the
        // previous value here would hide reminders forever after a missed unlock
        // notification. A failed dictionary query above still preserves state.
        locked = (dictionary["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}
