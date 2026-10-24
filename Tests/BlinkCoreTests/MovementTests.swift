import Foundation
import Testing
@testable import BlinkCore

/// Opt-in movement breaks: an hourly time away from the screen, between eye and long breaks.
@Suite("Movement breaks")
struct MovementTests {
    private func moving(
        short: TimeInterval = 60, movement: TimeInterval = 120, long: TimeInterval = 600,
        duration: TimeInterval = 10
    ) -> AppSettings {
        var settings = AppSettings.fast(short: short, long: long)
        settings.movementEnabled = true
        settings.movementInterval = movement
        settings.movementDuration = duration
        return settings
    }

    private func onDefaults() -> AppSettings {
        var settings = AppSettings()
        settings.movementEnabled = true
        return settings
    }

    // MARK: - Defaults and timing

    @Test("Movement is off by default and accrues nothing")
    func offByDefault() {
        let defaults = AppSettings()
        #expect(!defaults.movementEnabled)
        #expect(defaults.movementInterval == 3600)
        #expect(defaults.movementDuration == 120)
        #expect(defaults.movementActivity == .squats)

        var harness = Harness()
        harness.work(3600)
        #expect(harness.snapshot.pendingBreak == .short)
        #expect(harness.snapshot.movementRemaining == 3600)
    }

    @Test("A movement break becomes due after 60 counted minutes, not before")
    func dueAfterAnHour() {
        var settings = onDefaults()
        settings.shortEnabled = false
        var harness = Harness(settings: settings)
        harness.work(3599)
        #expect(harness.snapshot.pendingBreak == nil)
        #expect(harness.snapshot.movementRemaining == 1)

        harness.work(1)
        #expect(harness.snapshot.pendingBreak == .movement)
    }

    // MARK: - Priority

    @Test("A coincident eye break is consumed by the movement break, recording nothing")
    func movementConsumesCoincidentShort() {
        var harness = Harness(settings: moving())
        harness.work(60)
        harness.startBreak(.short)
        harness.work(5)
        harness.work(60)

        #expect(harness.snapshot.pendingBreak == .movement)
        #expect(harness.snapshot.shortRemaining == 60)
        #expect(harness.snapshot.summary.skipped == 0)
        #expect(harness.snapshot.summary.shortCompleted == 1)
    }

    @Test("A pending eye prompt is replaced when movement becomes due")
    func movementReplacesPendingShort() {
        var harness = Harness(settings: moving(short: 60, movement: 90))
        harness.work(60)
        #expect(harness.snapshot.pendingBreak == .short)

        harness.work(30)
        #expect(harness.snapshot.pendingBreak == .movement)
        #expect(harness.snapshot.shortRemaining == 60)
        #expect(harness.snapshot.summary.skipped == 0)
    }

    @Test("A due long break consumes a coincident movement break; completing it resets all")
    func longConsumesMovement() {
        var settings = moving(movement: 120, long: 120)
        settings.shortEnabled = false
        var harness = Harness(settings: settings)
        harness.work(120)

        #expect(harness.snapshot.pendingBreak == .long)
        #expect(harness.snapshot.movementRemaining == 120)
        #expect(harness.snapshot.summary.skipped == 0)

        harness.work(60)
        harness.startBreak(.long)
        harness.work(20)
        #expect(harness.snapshot.summary.longCompleted == 1)
        #expect(harness.snapshot.movementRemaining == 120)
        #expect(harness.snapshot.longRemaining == 120)
    }

    @Test("A pending movement prompt is replaced when the long break becomes due")
    func longReplacesPendingMovement() {
        var harness = Harness(settings: moving(short: 1000, movement: 100, long: 130))
        harness.work(100)
        #expect(harness.snapshot.pendingBreak == .movement)

        harness.work(30)
        #expect(harness.snapshot.pendingBreak == .long)
        #expect(harness.snapshot.movementRemaining == 100)
        #expect(harness.snapshot.summary.skipped == 0)
    }

    @Test("A due movement break waits behind a pending long break")
    func pendingLongIsNotReplaced() {
        var harness = Harness(settings: moving(short: 1000, movement: 150, long: 100))
        harness.work(100)
        #expect(harness.snapshot.pendingBreak == .long)

        harness.work(50)
        #expect(harness.snapshot.pendingBreak == .long)
    }

    // MARK: - Actions

    @Test("Completing a movement break resets movement and eye schedules and pauses the long one")
    func completionResetsMovementAndShort() {
        var harness = Harness(settings: moving())
        harness.work(60)
        harness.skip()
        harness.work(60)
        #expect(harness.snapshot.pendingBreak == .movement)

        harness.startBreak(.movement)
        harness.work(9)
        #expect(harness.snapshot.activeBreak?.kind == .movement)
        // Break time is not counted, so the long schedule does not advance.
        #expect(harness.snapshot.longRemaining == 600 - 120)

        harness.work(1)
        #expect(harness.snapshot.activeBreak == nil)
        #expect(harness.snapshot.summary.movementCompleted == 1)
        #expect(harness.completions(of: .movement) == 1)
        #expect(harness.snapshot.movementRemaining == 120)
        #expect(harness.snapshot.shortRemaining == 60)
        #expect(harness.snapshot.longRemaining == 600 - 120)
    }

    @Test("Skip and early end reset only the movement schedule and count as skipped")
    func skipAndEndEarly() {
        var harness = Harness(settings: moving(short: 1000))
        harness.work(120)
        #expect(harness.snapshot.pendingBreak == .movement)

        harness.skip()
        #expect(harness.snapshot.pendingBreak == nil)
        #expect(harness.snapshot.summary.skipped == 1)
        #expect(harness.snapshot.movementRemaining == 120)
        #expect(harness.snapshot.shortRemaining == 1000 - 120)
        #expect(harness.snapshot.longRemaining == 600 - 120)

        harness.work(120)
        harness.startBreak(.movement)
        harness.work(3)
        harness.endBreakEarly()
        #expect(harness.snapshot.summary.skipped == 2)
        #expect(harness.snapshot.summary.movementCompleted == 0)
        #expect(harness.snapshot.movementRemaining == 120)
        #expect(harness.snapshot.shortRemaining == 1000 - 240)
    }

    @Test("Snooze defers a movement break by five counted minutes")
    func snoozeDefers() {
        var settings = onDefaults()
        settings.shortEnabled = false
        var harness = Harness(settings: settings)
        harness.work(3600)
        harness.snooze()

        #expect(harness.snapshot.pendingBreak == nil)
        #expect(harness.snapshot.summary.snoozed == 1)
        #expect(harness.snapshot.movementRemaining == 300)
        harness.work(300)
        #expect(harness.snapshot.pendingBreak == .movement)
    }

    @Test("A movement break started from the menu runs for its own duration")
    func manualStart() {
        var harness = Harness(settings: onDefaults())
        harness.work(100)
        harness.startBreak(.movement)
        #expect(harness.snapshot.activeBreak == ActiveBreak(kind: .movement, remaining: 120))
        #expect(harness.snapshot.status == .onBreak)
    }

    @Test("Quiet mode hides a due movement break while its time still counts")
    func quietSuppresses() {
        var settings = onDefaults()
        settings.shortEnabled = false
        var harness = Harness(settings: settings)
        harness.setQuiet(minutes: nil)
        harness.work(3600)
        #expect(harness.snapshot.pendingBreak == nil)
        #expect(harness.snapshot.movementRemaining == 0)

        harness.resume()
        harness.work(9)
        #expect(harness.snapshot.pendingBreak == nil)
        harness.work(1)
        #expect(harness.snapshot.pendingBreak == .movement)
    }

    // MARK: - Absences

    @Test("A five-minute idle absence resets the movement schedule but not the long one")
    func idleResetsMovement() {
        var harness = Harness(settings: onDefaults())
        harness.work(1800)
        harness.sitIdle(300)

        #expect(harness.snapshot.status == .idle)
        #expect(harness.snapshot.movementRemaining == 3600)
        #expect(harness.snapshot.longRemaining == 7200 - 1800)
        #expect(harness.snapshot.summary.movementCompleted == 0)
    }

    @Test("A five-minute lock resets movement; a four-minute lock does not")
    func lockThreshold() {
        var settings = onDefaults()
        settings.idleDetectionEnabled = false

        var short = Harness(settings: settings)
        short.work(1800)
        short.locked(240)
        #expect(short.snapshot.movementRemaining == 3600 - 1800)
        #expect(short.snapshot.shortRemaining == 1200)

        var long = Harness(settings: settings)
        long.work(1800)
        long.locked(300)
        #expect(long.snapshot.movementRemaining == 3600)
        #expect(long.snapshot.longRemaining == 7200 - 1800)
    }

    @Test("A five-minute sleep resets movement")
    func sleepResetsMovement() {
        var harness = Harness(settings: onDefaults())
        harness.work(1800)
        harness.slept(300)
        #expect(harness.snapshot.movementRemaining == 3600)
    }

    @Test("A fifteen-minute absence resets every break schedule")
    func fifteenMinutesResetsAll() {
        var harness = Harness(settings: onDefaults())
        harness.work(3000)
        harness.sitIdle(900)

        #expect(harness.snapshot.shortRemaining == 1200)
        #expect(harness.snapshot.movementRemaining == 3600)
        #expect(harness.snapshot.longRemaining == 7200)
    }

    @Test("A due movement prompt is cleared by an absence long enough to reset it")
    func absenceClearsPendingMovement() {
        var settings = onDefaults()
        settings.shortEnabled = false
        var harness = Harness(settings: settings)
        harness.work(3600)
        #expect(harness.snapshot.pendingBreak == .movement)

        harness.sitIdle(300)
        harness.work(10)
        #expect(harness.snapshot.pendingBreak == nil)
        #expect(harness.snapshot.movementRemaining == 3590)
    }

    // MARK: - Settings

    @Test("Changing the activity keeps the schedule; changing timing restarts it")
    func activityDoesNotRestart() throws {
        var settings = onDefaults()
        var harness = Harness(settings: settings)
        harness.work(1000)

        settings.movementActivity = .walk
        try harness.updateSettings(settings)
        #expect(harness.snapshot.settings.movementActivity == .walk)
        #expect(harness.snapshot.movementRemaining == 2600)
        #expect(harness.snapshot.shortRemaining == 200)

        settings.movementInterval = 2400
        try harness.updateSettings(settings)
        #expect(harness.snapshot.movementRemaining == 2400)
        #expect(harness.snapshot.shortRemaining == 200)
    }

    @Test("Turning movement on starts a fresh interval without touching the others")
    func enablingStartsFresh() throws {
        var harness = Harness()
        harness.work(500)
        var settings = harness.snapshot.settings
        settings.movementEnabled = true
        try harness.updateSettings(settings)

        #expect(harness.snapshot.movementRemaining == 3600)
        #expect(harness.snapshot.shortRemaining == 700)
        #expect(harness.snapshot.longRemaining == 6700)
    }

    @Test("Turning movement off clears its pending prompt")
    func disablingClearsPrompt() throws {
        var settings = onDefaults()
        settings.shortEnabled = false
        var harness = Harness(settings: settings)
        harness.work(3600)
        #expect(harness.snapshot.pendingBreak == .movement)

        settings.movementEnabled = false
        try harness.updateSettings(settings)
        #expect(harness.snapshot.pendingBreak == nil)
    }

    @Test("Movement timings are validated and repaired like the others")
    func validation() throws {
        var settings = onDefaults()
        settings.movementInterval = 0
        settings.movementDuration = -5
        #expect(throws: SettingsValidationError.self) { try settings.validated() }
        do {
            try settings.validated()
        } catch let error as SettingsValidationError {
            #expect(error.fields == [.movementInterval, .movementDuration])
            #expect(error.message(for: .movementDuration) == "Movement break length must be longer than zero.")
        }

        let repaired = settings.repaired()
        #expect(repaired.movementInterval == 3600)
        #expect(repaired.movementDuration == 120)
        #expect(repaired.movementEnabled)
    }

    @Test("Restoring defaults turns movement back off but keeps onboarding")
    func restoreDefaults() {
        var settings = onDefaults()
        settings.onboardingComplete = true
        let restored = settings.restoringRecommendedDefaults()
        #expect(!restored.movementEnabled)
        #expect(restored.movementActivity == .squats)
        #expect(restored.onboardingComplete)
    }

    // MARK: - Persistence

    /// Removes the keys that builds before movement breaks never wrote.
    private func legacyJSON(_ state: EngineState) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        object.removeValue(forKey: "movement")
        var settings = try #require(object["settings"] as? [String: Any])
        for key in ["movementEnabled", "movementInterval", "movementDuration", "movementActivity"] {
            settings.removeValue(forKey: key)
        }
        object["settings"] = settings
        var summary = try #require(object["summary"] as? [String: Any])
        summary.removeValue(forKey: "movementCompleted")
        object["summary"] = summary
        if var absence = object["absence"] as? [String: Any] {
            absence.removeValue(forKey: "didResetMovement")
            object["absence"] = absence
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    @Test("State saved before movement breaks decodes with movement off and progress intact")
    func legacyStateDecodes() throws {
        var harness = Harness()
        harness.work(1200)
        harness.startBreak(.short)
        harness.work(20)
        harness.work(300)
        harness.locked(30)
        #expect(harness.engine.state.absence != nil)

        let decoded = try JSONDecoder().decode(EngineState.self, from: legacyJSON(harness.engine.state))
        #expect(!decoded.settings.movementEnabled)
        #expect(decoded.settings.movementActivity == .squats)
        #expect(decoded.settings.onboardingComplete)
        #expect(decoded.summary.shortCompleted == 1)
        #expect(decoded.summary.movementCompleted == 0)
        #expect(decoded.short == harness.engine.state.short)
        #expect(decoded.long == harness.engine.state.long)
        #expect(decoded.movement == Schedule(target: 3600))
        #expect(decoded.absence?.didResetMovement == false)

        let relaunched = Harness(resuming: decoded, at: harness.now.addingTimeInterval(60))
        #expect(relaunched.snapshot.longRemaining == 7200 - 1500)
        #expect(relaunched.snapshot.movementRemaining == 3600)
    }

    @Test("Fields that predate movement breaks are still required")
    func oldFieldsStayRequired() throws {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(EngineState())) as? [String: Any])
        var settings = try #require(object["settings"] as? [String: Any])
        settings.removeValue(forKey: "shortInterval")
        object["settings"] = settings
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(EngineState.self, from: data) }

        var summaryless = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(EngineState())) as? [String: Any])
        summaryless.removeValue(forKey: "summary")
        let missingSummary = try JSONSerialization.data(withJSONObject: summaryless)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(EngineState.self, from: missingSummary) }
    }

    @Test("A running movement break and its settings survive a relaunch")
    func roundTrip() throws {
        var settings = onDefaults()
        settings.movementActivity = .sitUps
        var harness = Harness(settings: settings)
        harness.startBreak(.movement)
        harness.work(30)

        let data = try JSONEncoder().encode(harness.engine.state)
        let restored = try JSONDecoder().decode(EngineState.self, from: data)
        #expect(restored == harness.engine.state)

        var relaunched = Harness(resuming: restored, at: harness.now.addingTimeInterval(600))
        #expect(relaunched.snapshot.activeBreak == ActiveBreak(kind: .movement, remaining: 90))
        #expect(relaunched.snapshot.settings.movementActivity == .sitUps)
        relaunched.work(90)
        #expect(relaunched.snapshot.summary.movementCompleted == 1)
    }

    @Test("Unusable movement state is repaired on load")
    func normalizeRepairs() {
        var state = EngineState(now: Harness.start, calendar: Harness.calendar)
        state.settings.onboardingComplete = true
        state.settings.movementEnabled = true
        state.movement.target = .nan
        state.movement.accrued = -40
        state.summary.movementCompleted = -3
        state.activeBreak = ActiveBreak(kind: .movement, remaining: 5000)

        let engine = ReminderEngine(state: state, now: Harness.start, calendar: Harness.calendar)
        #expect(engine.state.movement == Schedule(target: 3600))
        #expect(engine.snapshot.summary.movementCompleted == 0)
        #expect(engine.snapshot.activeBreak == ActiveBreak(kind: .movement, remaining: 120))

        var disabled = state
        disabled.settings.movementEnabled = false
        disabled.activeBreak = nil
        disabled.movement = Schedule(target: 3600)
        disabled.movement.accrued = 3600
        disabled.dueBreak = .movement
        let cleared = ReminderEngine(state: disabled, now: Harness.start, calendar: Harness.calendar)
        #expect(cleared.state.dueBreak == nil)
    }

    @Test("Midnight resets the movement counter without disturbing its schedule")
    func midnightResetsCounter() {
        var settings = onDefaults()
        settings.movementDuration = 10
        var harness = Harness(settings: settings, start: Harness.date(year: 2026, month: 9, day: 10, hour: 23, minute: 30))
        harness.work(100)
        harness.startBreak(.movement)
        harness.work(10)
        #expect(harness.snapshot.summary.movementCompleted == 1)

        harness.work(1800)
        #expect(harness.snapshot.summary.movementCompleted == 0)
        #expect(harness.snapshot.movementRemaining == 3600 - 1800)
    }
}
