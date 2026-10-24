import Foundation
import CoreGraphics
import Testing
import BlinkCore
@testable import Blink

@Suite("Native adapters")
struct AdapterTests {
    @Test("An unlocked session clears a latched lock even without an unlock notification")
    @MainActor
    func sessionUnlockReconciliation() {
        let console = kCGSessionOnConsoleKey as String
        var info: [String: Any]? = [console: true, "CGSSessionScreenIsLocked": true]
        let monitor = SystemMonitor(sessionInfo: { info })
        defer { monitor.stop() }
        #expect(monitor.isUnavailable)
        // A failed query cannot establish that the session became available.
        info = nil
        #expect(monitor.isUnavailable)
        // On this Mac the unlocked session omits the lock flag entirely.
        info = [console: true]
        #expect(!monitor.isUnavailable)
        info = [console: false]
        #expect(monitor.isUnavailable)
        info = [console: true]
        #expect(!monitor.isUnavailable)
    }

    @Test("Clock difference recovers a missed sleep event without misclassifying a stall")
    func missedSleepNotification() {
        var clock = AvailabilityClock(time: 0, suspendingTime: 0, isUnavailable: false)
        let stall = clock.sample(time: 60, suspendingTime: 60, isUnavailable: false)
        #expect(stall.unavailableElapsed == 0)
        let sleep = clock.sample(time: 3661, suspendingTime: 61, isUnavailable: false)
        #expect(sleep.elapsed == 3601)
        #expect(sleep.unavailableElapsed == 3600)
        let jitter = clock.sample(time: 3662, suspendingTime: 61.9999, isUnavailable: false)
        #expect(jitter.unavailableElapsed == 0)
    }

    @Test("Startup preserves an unreadable saved file until explicit reset")
    @MainActor
    func unreadableStateSurvivesStartup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BlinkRecovery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StateStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = Data("unreadable state to preserve".utf8)
        try original.write(to: store.file)
        let model = AppModel(store: store)
        model.start()
        #expect(model.needsStorageReset)
        #expect(try Data(contentsOf: store.file) == original)
        model.resetUnreadableStorage()
        #expect(!model.needsStorageReset)
        #expect(try store.load() != nil)
        model.stop()
    }

    @Test("Wake attributes the suspended interval to sleep, not screen time")
    func availabilityTransitions() {
        var clock = AvailabilityClock(time: 10, isUnavailable: false)
        #expect(clock.sample(time: 11, isUnavailable: false) == .init(elapsed: 1, unavailableElapsed: 0))
        #expect(clock.sample(time: 12, isUnavailable: true) == .init(elapsed: 1, unavailableElapsed: 0))
        #expect(clock.sample(time: 3612, isUnavailable: false) == .init(elapsed: 3600, unavailableElapsed: 3600))
        #expect(clock.sample(time: 3613, isUnavailable: false) == .init(elapsed: 1, unavailableElapsed: 0))
    }

    @Test("Availability integration resets screen-time schedules after sleep")
    func sleepWithEngine() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var engine = ReminderEngine(now: start)
        engine.completeOnboarding(now: start)
        var clock = AvailabilityClock(time: 0, isUnavailable: false)
        var sample = clock.sample(time: 600, isUnavailable: true)
        engine.tick(now: start.addingTimeInterval(600), elapsed: sample.elapsed, unavailableElapsed: sample.unavailableElapsed, idleSeconds: 0, isUnavailable: true)
        sample = clock.sample(time: 4200, isUnavailable: false)
        engine.tick(now: start.addingTimeInterval(4200), elapsed: sample.elapsed, unavailableElapsed: sample.unavailableElapsed, idleSeconds: 0, isUnavailable: false)
        #expect(engine.snapshot.shortRemaining == 1200)
        #expect(engine.snapshot.longRemaining == 7200)
        #expect(engine.snapshot.pendingBreak == nil)
    }

    @Test("Settings UI converts units and rejects invalid text")
    func settingsDraft() throws {
        var draft = SettingsDraft(AppSettings())
        #expect(try draft.validated() == AppSettings())
        draft.shortInterval = "1.5"
        draft.longDuration = "2.5"
        draft.movementInterval = "45"
        draft.movementDuration = "1.5"
        #expect(try draft.validated().shortInterval == 90)
        #expect(try draft.validated().longDuration == 150)
        #expect(try draft.validated().movementInterval == 2700)
        #expect(try draft.validated().movementDuration == 90)
        for invalid in ["0", "-1", "NaN", "inf", "hello", "", "1e999"] {
            draft.shortInterval = invalid
            #expect(throws: (any Error).self) { try draft.validated() }
        }
        draft.shortInterval = "20"
        for invalid in ["0", "-1", "NaN", "inf", "hello", "", "1e999"] {
            draft.movementInterval = invalid
            #expect(throws: (any Error).self) { try draft.validated() }
        }
        draft.movementInterval = "60"
        draft.movementDuration = "0"
        #expect(throws: (any Error).self) { try draft.validated() }
    }

    @Test("Atomic storage restores progress and restricts file access")
    func persistenceRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BlinkTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StateStore(directory: directory)
        #expect(try store.load() == nil)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var engine = ReminderEngine(now: now)
        engine.completeOnboarding(now: now)
        engine.tick(now: now.addingTimeInterval(600), elapsed: 600, unavailableElapsed: 0, idleSeconds: 0, isUnavailable: false)
        try store.save(engine.state)
        let loaded = try store.load()
        let saved = try #require(loaded)
        #expect(saved == engine.state)
        let reloaded = ReminderEngine(state: saved, now: now.addingTimeInterval(3600))
        #expect(reloaded.snapshot.shortRemaining == 600)
        #expect(reloaded.snapshot.settings.onboardingComplete)
        let permissions = try FileManager.default.attributesOfItem(atPath: store.file.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["state.json"])
    }

    @Test("Malformed or unknown-version state fails explicitly")
    func corruptState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BlinkTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StateStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.file)
        #expect(throws: (any Error).self) { try store.load() }
    }
}
