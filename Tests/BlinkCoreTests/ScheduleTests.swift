import Foundation
import Testing
@testable import BlinkCore

/// Acceptance checks 1-3: default timings, collisions, and the prompt actions.
@Suite("Schedules")
struct ScheduleTests {
    @Test("Short break becomes due after 20 counted minutes, not before")
    func shortBreakDueAtTwentyMinutes() {
        var harness = Harness()
        harness.work(1199)
        #expect(harness.snapshot.pendingBreak == nil)
        #expect(harness.snapshot.shortRemaining == 1)

        harness.work(1)
        #expect(harness.snapshot.pendingBreak == .short)
        #expect(harness.snapshot.status == .running)
    }

    @Test("Long break becomes due after 120 counted minutes")
    func longBreakDueAtTwoHours() {
        var harness = Harness()
        harness.work(7199)
        #expect(harness.snapshot.pendingBreak == .short)

        harness.work(1)
        #expect(harness.snapshot.pendingBreak == .long)
    }

    @Test("A completed short break leaves long-break progress intact")
    func shortBreakDoesNotEraseLongProgress() {
        var harness = Harness()
        harness.work(1200)
        harness.startBreak(.short)
        harness.work(20)

        #expect(harness.snapshot.summary.shortCompleted == 1)
        #expect(harness.snapshot.shortRemaining == 1200)
        // The 20 minutes stay on the long schedule, and the break itself counted for nothing.
        #expect(harness.snapshot.longRemaining == 7200 - 1200)
    }

    @Test("A due long break replaces a coincident short occurrence, recording neither")
    func longBreakReplacesCoincidentShort() {
        var harness = Harness(settings: .fast(short: 60, long: 60))
        harness.work(60)

        #expect(harness.snapshot.pendingBreak == .long)
        #expect(harness.snapshot.summary.skipped == 0)
        #expect(harness.snapshot.summary.shortCompleted == 0)
        // Consumed and given a fresh interval, so no second prompt follows the long one.
        #expect(harness.snapshot.shortRemaining == 60)
    }

    @Test("An unanswered prompt stays available without re-firing")
    func unansweredPromptIsNotRepeated() {
        var harness = Harness()
        harness.work(1200)
        _ = harness.drain()

        harness.work(600)
        #expect(harness.snapshot.pendingBreak == .short)
        // Nothing re-announces it: no cues, no chimes.
        #expect(harness.effects.isEmpty)
    }

    @Test("Snooze defers the occurrence by five counted minutes and counts each action")
    func snoozeDefersByFiveCountedMinutes() {
        var harness = Harness()
        harness.work(1200)
        harness.snooze()

        #expect(harness.snapshot.pendingBreak == nil)
        #expect(harness.snapshot.summary.snoozed == 1)
        #expect(harness.snapshot.shortRemaining == 300)

        harness.work(299)
        #expect(harness.snapshot.pendingBreak == nil)
        harness.work(1)
        #expect(harness.snapshot.pendingBreak == .short)

        harness.snooze()
        #expect(harness.snapshot.summary.snoozed == 2)
        #expect(harness.snapshot.shortRemaining == 300)
    }

    @Test("A snoozed prompt does not resurface on wall time spent away from the desk")
    func snoozeIsCountedTimeNotWallTime() {
        var harness = Harness()
        harness.work(1200)
        harness.snooze()

        // Ten seconds locked: real time passes, counted screen time does not, and the
        // absence is too short to reset anything.
        harness.locked(10)
        #expect(harness.snapshot.shortRemaining == 300)
        #expect(harness.snapshot.pendingBreak == nil)
    }

    @Test("Skip schedules the next normal interval and records no rest")
    func skipRecordsNoRest() {
        var harness = Harness()
        harness.work(1200)
        harness.skip()

        #expect(harness.snapshot.summary.skipped == 1)
        #expect(harness.snapshot.summary.shortCompleted == 0)
        #expect(harness.snapshot.pendingBreak == nil)
        #expect(harness.snapshot.shortRemaining == 1200)
        // A short-break action never resets the long schedule.
        #expect(harness.snapshot.longRemaining == 7200 - 1200)
    }

    @Test("Ending a started break early counts as skipped, not completed")
    func endingEarlyCountsAsSkipped() {
        var harness = Harness()
        harness.work(1200)
        harness.startBreak(.short)
        harness.work(5)
        harness.endBreakEarly()

        #expect(harness.snapshot.summary.skipped == 1)
        #expect(harness.snapshot.summary.shortCompleted == 0)
        #expect(harness.snapshot.activeBreak == nil)
        #expect(harness.snapshot.shortRemaining == 1200)
        #expect(harness.snapshot.longRemaining == 7200 - 1200)
    }

    @Test("A completed long break resets both schedules")
    func completedLongBreakResetsBoth() {
        var harness = Harness()
        harness.work(600)
        harness.startBreak(.long)
        harness.work(900)

        #expect(harness.snapshot.summary.longCompleted == 1)
        #expect(harness.completions(of: .long) == 1)
        #expect(harness.snapshot.shortRemaining == 1200)
        #expect(harness.snapshot.longRemaining == 7200)
    }

    @Test("Ending a long break early resets only the long schedule")
    func endingLongBreakEarlyLeavesShortAlone() {
        var harness = Harness()
        harness.work(600)
        harness.startBreak(.long)
        harness.work(10)
        harness.endBreakEarly()

        #expect(harness.snapshot.summary.skipped == 1)
        #expect(harness.snapshot.longRemaining == 7200)
        #expect(harness.snapshot.shortRemaining == 1200 - 600)
    }

    @Test("The countdown starts only when the user chooses Start")
    func promptDoesNotStartItself() {
        var harness = Harness()
        harness.work(1200)
        harness.work(120)

        #expect(harness.snapshot.activeBreak == nil)
        #expect(harness.snapshot.pendingBreak == .short)
        #expect(harness.snapshot.summary.shortCompleted == 0)
    }

    @Test("Both schedules pause while a break is running")
    func breaksPauseBothSchedules() {
        var harness = Harness()
        harness.work(600)
        harness.startBreak(.long)
        harness.work(300)

        #expect(harness.snapshot.activeBreak?.remaining == 600)
        // Neither schedule moved during the five minutes of break.
        #expect(harness.snapshot.shortRemaining == 1200 - 600)
        #expect(harness.snapshot.longRemaining == 7200 - 600)
    }
}
