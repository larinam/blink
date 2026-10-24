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
    private let sessionInfo: () -> [String: Any]?

    init(sessionInfo: @escaping () -> [String: Any]? = {
        CGSessionCopyCurrentDictionary() as? [String: Any]
    }) {
        self.sessionInfo = sessionInfo
        refreshSession()
        observeWorkspace(NSWorkspace.willSleepNotification) { $0.sleeping = true }
        observeWorkspace(NSWorkspace.didWakeNotification) { $0.sleeping = false }
        observeWorkspace(NSWorkspace.screensDidSleepNotification) { $0.displaySleeping = true }
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
        return sleeping || displaySleeping || sessionInactive || locked
    }

    var idleSeconds: TimeInterval {
        let events: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .leftMouseDragged, .rightMouseDragged]
        let values = events.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .filter { $0.isFinite && $0 >= 0 }
        return values.min() ?? 0
    }

    func stop() {
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        applicationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        workspaceObservers.removeAll()
        distributedObservers.removeAll()
        applicationObservers.removeAll()
    }

    private func observeWorkspace(_ name: Notification.Name, change: @escaping @MainActor (SystemMonitor) -> Void) {
        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                change(self)
                self.onChange?()
            }
        })
    }

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
