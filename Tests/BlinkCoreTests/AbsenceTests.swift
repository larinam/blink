import Foundation
import Testing
@testable import BlinkCore

/// Acceptance checks 4 and 5: idle, lock and sleep credit.
@Suite("Absences")
struct AbsenceTests {
    @Test("A five-minute idle period resets the short schedule and removes its own time")
    func fiveMinuteIdleResetsShortAndRefundsCountedTime() {
        var harness = Harness()
        harness.work(600)
        harness.sitIdle(300)

        #expect(harness.snapshot.status == .idle)
        #expect(harness.snapshot.shortRemaining == 1200)
        // The absence began at the last input, so the idle minutes come back off the long
        // schedule while the ten minutes of real work stay on it.
        #expect(harness.snapshot.longRemaining == 7200 - 600)
    }

    @Test("A fifteen-minute idle period resets both schedules")
    func fifteenMinuteIdleResetsBoth() {
        var harness = Harness()
        harness.work(3600)
        harness.sitIdle(900)

        #expect(harness.snapshot.shortRemaining == 1200)
        #expect(harness.snapshot.longRemaining == 7200)
    }

    @Test("Reminders stop while idle and resume after a settling period")
    func remindersStopWhileIdle() {
        var harness = Harness()
        harness.work(1200)
        #expect(harness.snapshot.pendingBreak == .short)

        harness.sitIdle(400)
        #expect(harness.snapshot.pendingBreak == nil)
        #expect(harness.snapshot.status == .idle)

        harness.work(1)
        // Back at the desk, but the ten-second grace has not elapsed yet.
        #expect(harness.snapshot.status == .running)
        #expect(harness.snapshot.pendingBreak == nil)
    }

    @Test("Disabling idle detection keeps quiet reading time counted")
    func disabledIdleDetectionPreservesReadingTime() {
        var settings = AppSettings()
        settings.idleDetectionEnabled = false
        var harness = Harness(settings: settings)

        harness.sitIdle(1200)
        #expect(harness.snapshot.status == .running)
        #expect(harness.snapshot.pendingBreak == .short)
    }

    @Test("Lock and sleep detection stay active when idle detection is off")
    func lockStillCountsWithIdleDetectionOff() {
        var settings = AppSettings()
        settings.idleDetectionEnabled = false
        var harness = Harness(settings: settings)

        harness.sitIdle(600)
        harness.locked(30)
        harness.work(1)
        #expect(harness.snapshot.shortRemaining == 1200 - 1)
        #expect(harness.snapshot.longRemaining == 7200 - 601)
    }

    @Test("An observed absence of at least 20 seconds resets the short schedule")
    func twentySecondLockResetsShort() {
        var harness = Harness()
        harness.work(600)
        harness.locked(30)
        harness.work(1)

        #expect(harness.snapshot.shortRemaining == 1200 - 1)
        #expect(harness.snapshot.longRemaining == 7200 - 601)
    }

    @Test("An absence under 20 seconds resets nothing")
    func briefLockResetsNothing() {
        var harness = Harness()
        harness.work(600)
        harness.locked(10)
        harness.work(1)

        #expect(harness.snapshot.shortRemaining == 1200 - 601)
        #expect(harness.snapshot.longRemaining == 7200 - 601)
    }

    @Test("A sleep span is never credited as screen time")
    func sleepIsNotScreenTime() {
        var harness = Harness()
        harness.work(600)
        // One minute asleep: long enough to reset the short schedule, far too short to
        // reset the long one — and worth nothing at all on either.
        harness.slept(60)

        #expect(harness.snapshot.shortRemaining == 1200)
        #expect(harness.snapshot.longRemaining == 7200 - 600)
        #expect(harness.snapshot.pendingBreak == nil)
    }

    @Test("An hour of sleep resets both schedules without advancing either")
    func longSleepResetsBoth() {
        var harness = Harness()
        harness.work(3000)
        harness.slept(3600)

        #expect(harness.snapshot.shortRemaining == 1200)
        #expect(harness.snapshot.longRemaining == 7200)
        #expect(harness.snapshot.pendingBreak == nil)
    }

    @Test("Sleep and the idle period spanning it are not credited twice")
    func sleepAndIdleAreNotDoubleCounted() {
        var harness = Harness()
        harness.work(600)
        // The user stops typing, then the Mac sleeps 60 seconds later. Only that minute
        // was ever counted as screen time, so only that minute may be taken back.
        harness.sitIdle(60)
        harness.slept(3600)

        #expect(harness.snapshot.shortRemaining == 1200)
        #expect(harness.snapshot.longRemaining == 7200)

        // The full reset above hides any rollback error in long-schedule progress.
        // A brief sleep leaves that schedule intact so its counted time can be checked.
        var brief = Harness()
        brief.work(600)
        brief.sitIdle(60)
        brief.slept(30)
        #expect(brief.snapshot.longRemaining == 7200 - 660)
    }

    @Test("A finished long break is not immediately rewound by the idle it caused")
    func completedBreakIsNotRewoundByIdle() {
        var harness = Harness()
        harness.startBreak(.long)
        harness.sitIdle(900)

        #expect(harness.snapshot.summary.longCompleted == 1)
        #expect(harness.snapshot.shortRemaining == 1200)
        #expect(harness.snapshot.longRemaining == 7200)

        // Still away afterwards: the absence continues, but there is nothing left to undo.
        harness.sitIdle(400)
        #expect(harness.snapshot.status == .idle)
        #expect(harness.snapshot.shortRemaining == 1200)
        #expect(harness.snapshot.longRemaining == 7200)
    }

    @Test("A break that finishes while locked completes silently and never chimes later")
    func chimeIsSuppressedWhileUnavailable() {
        var harness = Harness()
        harness.startBreak(.short)
        harness.locked(20)

        #expect(harness.snapshot.summary.shortCompleted == 1)
        #expect(harness.completions(of: .short) == 0)

        harness.work(120)
        #expect(harness.completions(of: .short) == 0)
    }

    @Test("A break countdown keeps running through sleep")
    func breakCountdownContinuesThroughSleep() {
        var harness = Harness()
        harness.startBreak(.long)
        harness.work(60)
        harness.slept(1800)

        #expect(harness.snapshot.activeBreak == nil)
        #expect(harness.snapshot.summary.longCompleted == 1)
        #expect(harness.snapshot.summary.skipped == 0)
    }
}
