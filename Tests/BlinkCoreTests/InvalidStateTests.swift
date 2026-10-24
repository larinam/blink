import Foundation
import Testing
@testable import BlinkCore

/// State that decodes cleanly but cannot be true — a hand-edited file, or one written by a
/// build with a different idea of the schema. The store's job is to reject what will not
/// decode; this is the engine's job: never start in a condition it cannot recover from.
///
/// Every case here checks the same two things — that the engine still schedules, and that
/// nothing became silently permanent.
@Suite("Invalid decoded state")
struct InvalidStateTests {
    /// Builds an engine from state mutated however the test likes.
    private func engine(_ mutate: (inout EngineState) -> Void) -> ReminderEngine {
        var state = EngineState(now: Harness.start, calendar: Harness.calendar)
        state.settings.onboardingComplete = true
        mutate(&state)
        return ReminderEngine(state: state, now: Harness.start, calendar: Harness.calendar)
    }

    /// Runs enough ordinary screen time for a default short break to come due.
    private func runToShortBreak(_ engine: inout ReminderEngine) -> BreakKind? {
        var now = Harness.start
        for _ in 0..<1300 {
            now += 1
            engine.tick(now: now, elapsed: 1, unavailableElapsed: 0, idleSeconds: 0, isUnavailable: false)
        }
        return engine.snapshot.pendingBreak
    }

    @Test("A non-finite schedule target does not silence reminders forever")
    func nonFiniteTargetIsRepaired() {
        // Every comparison against NaN is false, so an unrepaired target would mean the
        // occurrence never comes due and no reminder ever appears again.
        var subject = engine { $0.short.target = .nan; $0.long.target = .infinity }

        #expect(subject.snapshot.shortRemaining == 1200)
        #expect(subject.snapshot.longRemaining == 7200)
        #expect(runToShortBreak(&subject) == .short)
    }

    @Test("A zero or negative target does not produce a permanently due prompt")
    func nonPositiveTargetIsRepaired() {
        var subject = engine { $0.short.target = 0; $0.long.target = -600 }

        #expect(subject.snapshot.shortRemaining == 1200)
        #expect(subject.snapshot.longRemaining == 7200)
        #expect(runToShortBreak(&subject) == .short)
    }

    @Test("Non-finite or negative accrued time is discarded")
    func invalidAccruedIsRepaired() {
        var subject = engine { $0.short.accrued = .nan; $0.long.accrued = -5000; $0.blink.accrued = .infinity }

        #expect(subject.snapshot.shortRemaining == 1200)
        #expect(subject.snapshot.longRemaining == 7200)
        #expect(runToShortBreak(&subject) == .short)
    }

    @Test("Invalid settings are repaired rather than refused")
    func invalidSettingsAreRepaired() {
        let subject = engine { $0.settings.shortInterval = 0; $0.settings.blinkInterval = .nan; $0.settings.longDuration = -1 }

        #expect(subject.snapshot.settings.shortInterval == 1200)
        #expect(subject.snapshot.settings.blinkInterval == 60)
        #expect(subject.snapshot.settings.longDuration == 900)
        // Repair leaves untouched fields alone, and the result is valid.
        #expect(throws: Never.self) { try subject.snapshot.settings.validated() }
    }

    @Test("A non-finite grace period does not suppress every reminder")
    func nonFiniteGraceIsRepaired() {
        // `max(0, NaN - elapsed)` is NaN and `NaN <= 0` is false, so an unrepaired grace
        // would gate every prompt and cue for the life of the install.
        var subject = engine { $0.graceRemaining = .nan; $0.short.accrued = 1200 }

        #expect(subject.snapshot.pendingBreak == nil)  // the launch grace, which does decay
        var now = Harness.start
        for _ in 0..<11 {
            now += 1
            subject.tick(now: now, elapsed: 1, unavailableElapsed: 0, idleSeconds: 0, isUnavailable: false)
        }
        #expect(subject.snapshot.pendingBreak == .short)
    }

    @Test("An absurd grace period is clamped to the ten seconds it is meant to be")
    func oversizedGraceIsClamped() {
        var subject = engine { $0.graceRemaining = 86_400; $0.short.accrued = 1200 }

        var now = Harness.start
        for _ in 0..<11 {
            now += 1
            subject.tick(now: now, elapsed: 1, unavailableElapsed: 0, idleSeconds: 0, isUnavailable: false)
        }
        #expect(subject.snapshot.pendingBreak == .short)
    }

    @Test("An unusable active break is dropped, not credited")
    func unusableActiveBreakIsDropped() {
        let nan = engine { $0.activeBreak = ActiveBreak(kind: .long, remaining: .nan) }
        #expect(nan.snapshot.activeBreak == nil)
        #expect(nan.snapshot.summary.longCompleted == 0)
        #expect(nan.snapshot.summary.skipped == 0)

        let negative = engine { $0.activeBreak = ActiveBreak(kind: .short, remaining: -30) }
        #expect(negative.snapshot.activeBreak == nil)
        #expect(negative.snapshot.summary.shortCompleted == 0)
    }

    @Test("An active break longer than its own duration is bounded")
    func oversizedActiveBreakIsClamped() {
        // Otherwise a full-screen overlay could sit there for a simulated year.
        var subject = engine { $0.activeBreak = ActiveBreak(kind: .short, remaining: 31_536_000) }
        #expect(subject.snapshot.activeBreak?.remaining == 20)

        var now = Harness.start
        for _ in 0..<20 {
            now += 1
            subject.tick(now: now, elapsed: 1, unavailableElapsed: 0, idleSeconds: 0, isUnavailable: false)
        }
        #expect(subject.snapshot.activeBreak == nil)
        #expect(subject.snapshot.summary.shortCompleted == 1)
    }

    @Test("A prompt for a disabled break is cleared")
    func staleDueBreakForDisabledKindIsCleared() {
        // A disabled schedule never becomes due, so nothing else would ever clear it.
        let subject = engine { $0.settings.shortEnabled = false; $0.dueBreak = .short }

        #expect(subject.snapshot.pendingBreak == nil)
        #expect(subject.state.dueBreak == nil)
    }

    @Test("A summary dated in the future is replaced so counters can still reset")
    func futureSummaryIsReplaced() {
        let subject = engine {
            $0.summary = DailySummary(day: Harness.date(year: 2030, month: 1, day: 1), shortCompleted: 99)
        }

        #expect(subject.snapshot.summary.day == Harness.calendar.startOfDay(for: Harness.start))
        #expect(subject.snapshot.summary.shortCompleted == 0)
    }

    @Test("Negative counters are clamped rather than displayed")
    func negativeCountersAreClamped() {
        let subject = engine {
            $0.summary = DailySummary(
                day: Harness.calendar.startOfDay(for: Harness.start),
                shortCompleted: -3, longCompleted: -1, skipped: -7, snoozed: -2
            )
        }

        #expect(subject.snapshot.summary.shortCompleted == 0)
        #expect(subject.snapshot.summary.longCompleted == 0)
        #expect(subject.snapshot.summary.skipped == 0)
        #expect(subject.snapshot.summary.snoozed == 0)
    }

    @Test("A quiet expiry with no quiet period is not shown")
    func orphanedQuietExpiryIsCleared() {
        let subject = engine { $0.quietActive = false; $0.quietUntil = Harness.start.addingTimeInterval(3600) }

        #expect(!subject.snapshot.isQuiet)
        #expect(subject.snapshot.quietUntil == nil)
    }

    @Test("A non-finite quiet expiry becomes an indefinite quiet period, not a stuck one")
    func nonFiniteQuietExpiryIsCleared() {
        let subject = engine {
            $0.quietActive = true
            $0.quietUntil = Date(timeIntervalSinceReferenceDate: .infinity)
        }

        #expect(subject.snapshot.isQuiet)
        #expect(subject.snapshot.quietUntil == nil)
    }

    @Test("Thoroughly corrupt state still schedules normally")
    func everythingWrongAtOnceStillRecovers() {
        var subject = engine {
            $0.settings.shortInterval = .nan
            $0.settings.longInterval = 0
            $0.settings.blinkInterval = -60
            $0.short = Schedule(target: .nan)
            $0.short.accrued = .infinity
            $0.long.target = -1
            $0.blink.accrued = .nan
            $0.graceRemaining = .nan
            $0.countedSinceLastInput = .nan
            $0.activeBreak = ActiveBreak(kind: .long, remaining: .nan)
            $0.dueBreak = .long
            $0.quietUntil = Date(timeIntervalSinceReferenceDate: -.infinity)
            $0.summary = DailySummary(day: Harness.date(year: 2099, month: 12, day: 31), skipped: -4)
        }

        #expect(throws: Never.self) { try subject.snapshot.settings.validated() }
        #expect(subject.snapshot.activeBreak == nil)
        #expect(subject.snapshot.summary == DailySummary(now: Harness.start, calendar: Harness.calendar))
        #expect(subject.snapshot.shortRemaining == 1200)
        #expect(subject.snapshot.longRemaining == 7200)

        // The file claimed a long break was owed, but its schedule sits at zero, so no
        // such break was ever earned. Scheduling starts clean.
        #expect(subject.state.dueBreak == nil)
        #expect(runToShortBreak(&subject) == .short)
    }

    @Test("A prompt the schedules cannot account for is cleared")
    func unearnedDueBreakIsCleared() {
        let subject = engine { $0.dueBreak = .long }

        #expect(subject.state.dueBreak == nil)
        #expect(subject.snapshot.pendingBreak == nil)
    }

    @Test("A genuinely earned prompt in decoded state is kept")
    func earnedDueBreakIsKept() {
        let subject = engine { $0.long.accrued = 7200; $0.dueBreak = .long }

        #expect(subject.state.dueBreak == .long)
    }

    @Test("A due break survives an idle absence that rolls its schedule back")
    func owedBreakSurvivesIdleRollback() {
        // The invariant the normalization relies on, checked from the live side: the idle
        // rollback can never take a due schedule back below its target, because it removes
        // only counted time that the same schedule accrued.
        var harness = Harness()
        harness.work(7200)
        #expect(harness.snapshot.pendingBreak == .long)

        harness.sitIdle(300)
        harness.work(11)
        #expect(harness.snapshot.pendingBreak == .long)
        #expect(harness.snapshot.longRemaining == 0)
    }

    @Test("Valid state passes through normalization untouched")
    func validStateIsNotDisturbed() {
        var harness = Harness()
        harness.work(1000)
        let saved = harness.engine.state

        let restored = ReminderEngine(state: saved, now: harness.now, calendar: Harness.calendar)
        #expect(restored.snapshot.shortRemaining == saved.short.remaining)
        #expect(restored.snapshot.longRemaining == saved.long.remaining)
        #expect(restored.snapshot.summary == saved.summary)
        #expect(restored.snapshot.settings == saved.settings)
    }
}
