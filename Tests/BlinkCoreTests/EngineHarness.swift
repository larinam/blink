import Foundation
@testable import BlinkCore

/// Drives the engine the way the real adapter does, with time entirely under the test's
/// control: a monotonic `elapsed`, an `unavailableElapsed` accumulated across the tick,
/// and an `idleSeconds` that grows while nobody touches the keyboard.
struct Harness {
    var engine: ReminderEngine
    var now: Date
    /// Seconds since the last keyboard or pointer input, as the adapter would report.
    var idleSeconds: TimeInterval = 0
    private(set) var effects: [EngineEffect] = []

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return calendar
    }()

    /// 2026-09-10 09:00 local. Fixed so day-boundary tests are reproducible.
    static let start = date(year: 2026, month: 9, day: 10, hour: 9)

    static func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return calendar.date(from: components)!
    }

    init(settings: AppSettings = AppSettings(), start: Date = Harness.start, onboarded: Bool = true) {
        self.now = start
        var state = EngineState(now: start, calendar: Harness.calendar)
        state.settings = settings
        self.engine = ReminderEngine(state: state, now: start, calendar: Harness.calendar)
        if onboarded { engine.completeOnboarding(now: start) }
    }

    /// Restores from the engine's own persisted bytes, as a relaunch does.
    init(resuming state: EngineState, at now: Date) {
        self.now = now
        self.engine = ReminderEngine(state: state, now: now, calendar: Harness.calendar)
    }

    var snapshot: EngineSnapshot { engine.snapshot }

    mutating func drain() -> [EngineEffect] {
        defer { effects = [] }
        return effects
    }

    // MARK: - Time

    /// The user is at the keyboard: available, and producing input each step.
    mutating func work(_ duration: TimeInterval, step: TimeInterval = 1) {
        run(duration, step: step, unavailable: false, receivingInput: true)
    }

    /// Available and awake, but nobody is touching anything.
    mutating func sitIdle(_ duration: TimeInterval, step: TimeInterval = 1) {
        run(duration, step: step, unavailable: false, receivingInput: false)
    }

    /// Locked, with the process still ticking — the screen-lock case.
    mutating func locked(_ duration: TimeInterval, step: TimeInterval = 1) {
        run(duration, step: step, unavailable: true, receivingInput: false)
    }

    /// System sleep: the process is suspended, so no ticks happen at all and the adapter
    /// reports the entire span on the single tick that follows the wake.
    mutating func slept(_ duration: TimeInterval) {
        now += duration
        idleSeconds += duration
        effects += engine.tick(
            now: now,
            elapsed: duration,
            unavailableElapsed: duration,
            idleSeconds: idleSeconds,
            isUnavailable: false
        )
    }

    /// A single deliberate tick, for asserting on one step in isolation.
    mutating func tick(step: TimeInterval = 1, unavailable: Bool = false, receivingInput: Bool = true) {
        run(step, step: step, unavailable: unavailable, receivingInput: receivingInput)
    }

    private mutating func run(_ duration: TimeInterval, step: TimeInterval, unavailable: Bool, receivingInput: Bool) {
        var remaining = duration
        while remaining > 0 {
            let slice = min(step, remaining)
            remaining -= slice
            now += slice
            if receivingInput {
                idleSeconds = 0
            } else {
                idleSeconds += slice
            }
            effects += engine.tick(
                now: now,
                elapsed: slice,
                unavailableElapsed: unavailable ? slice : 0,
                idleSeconds: idleSeconds,
                isUnavailable: unavailable
            )
        }
    }

    // MARK: - Convenience

    mutating func startBreak(_ kind: BreakKind) { engine.startBreak(kind, now: now) }
    mutating func snooze() { engine.snooze(now: now) }
    mutating func skip() { engine.skip(now: now) }
    mutating func endBreakEarly() { engine.endBreakEarly(now: now) }
    mutating func setQuiet(minutes: Double?) {
        engine.setQuiet(until: minutes.map { now.addingTimeInterval($0 * 60) }, now: now)
    }
    mutating func resume() { engine.resume(now: now) }
    mutating func updateSettings(_ settings: AppSettings) throws {
        try engine.updateSettings(settings, now: now)
    }

    var blinkCount: Int { effects.filter { $0 == .blink }.count }
    func completions(of kind: BreakKind) -> Int { effects.filter { $0 == .breakCompleted(kind) }.count }
}

extension AppSettings {
    /// Small intervals keep collision and priority tests readable.
    static func fast(short: TimeInterval = 60, long: TimeInterval = 120, blink: TimeInterval = 10) -> AppSettings {
        var settings = AppSettings()
        settings.shortInterval = short
        settings.longInterval = long
        settings.blinkInterval = blink
        settings.shortDuration = 5
        settings.longDuration = 20
        return settings
    }
}
