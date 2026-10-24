import Foundation
import Testing
@testable import BlinkCore

/// Overlapping quiet periods, absences, breaks and due occurrences must present
/// at most one reminder without stranding or duplicating an occurrence.
@Suite("Simultaneous states")
struct SimultaneousStateTests {
    @Test("Three reminders falling due at the same instant produce one prompt")
    func allThreeDueAtOnce() {
        var harness = Harness(settings: .fast(short: 60, long: 60, blink: 60))
        harness.work(60)

        #expect(harness.snapshot.pendingBreak == .long)
        #expect(harness.blinkCount == 0)
        #expect(harness.snapshot.summary == DailySummary(now: Harness.start, calendar: Harness.calendar))
    }

    @Test("Quiet mode and an idle absence together report quiet and suppress everything")
    func quietAndIdleTogether() {
        var harness = Harness()
        harness.setQuiet(minutes: nil)
        harness.sitIdle(1200)

        #expect(harness.snapshot.status == .quiet)
        #expect(harness.snapshot.pendingBreak == nil)
        #expect(harness.blinkCount == 0)
        // Idle time is not eligible screen time, quiet mode or not.
        #expect(harness.snapshot.shortRemaining == 1200)
    }

    @Test("Quiet expiring during an absence delays the prompt until the user is back")
    func quietExpiringDuringAnAbsence() {
        var harness = Harness()
        harness.work(1200)
        harness.setQuiet(minutes: 15)
        // Briefly locked — under every reset threshold, so the occurrence survives.
        harness.locked(10)

        // One coalesced tick that both ends the lock and passes the quiet expiry.
        harness.tick(step: 900)
        #expect(!harness.snapshot.isQuiet)
        #expect(harness.snapshot.pendingBreak == nil)

        harness.work(9)
        #expect(harness.snapshot.pendingBreak == nil)
        harness.work(1)
        #expect(harness.snapshot.pendingBreak == .short)
    }

    @Test("Midnight passing during quiet mode resets counters and keeps quiet running")
    func midnightDuringQuiet() {
        var harness = Harness(start: Harness.date(year: 2026, month: 9, day: 10, hour: 23, minute: 50))
        harness.startBreak(.short)
        harness.work(20)
        #expect(harness.snapshot.summary.shortCompleted == 1)

        harness.setQuiet(minutes: nil)
        harness.work(1200)

        #expect(harness.snapshot.isQuiet)
        #expect(harness.snapshot.summary.shortCompleted == 0)
        #expect(harness.snapshot.summary.day == Harness.date(year: 2026, month: 9, day: 11))
    }

    @Test("Changing settings during a break leaves that break's countdown alone")
    func settingsChangeDuringABreak() throws {
        var harness = Harness()
        harness.work(600)
        harness.startBreak(.short)
        harness.work(5)
        #expect(harness.snapshot.activeBreak?.remaining == 15)

        var settings = harness.snapshot.settings
        settings.shortDuration = 60
        try harness.updateSettings(settings)

        // The running countdown is untouched; only the schedule restarts.
        #expect(harness.snapshot.activeBreak?.remaining == 15)
        #expect(harness.snapshot.shortRemaining == 1200)

        harness.work(15)
        #expect(harness.snapshot.summary.shortCompleted == 1)
    }

    @Test("A break running while the screen locks and then the session sleeps still completes once")
    func breakThroughLockThenSleep() {
        var harness = Harness()
        harness.startBreak(.long)
        harness.work(100)
        harness.locked(200)
        harness.slept(600)

        #expect(harness.snapshot.activeBreak == nil)
        #expect(harness.snapshot.summary.longCompleted == 1)
        #expect(harness.snapshot.summary.skipped == 0)
        #expect(harness.completions(of: .long) == 0)

        harness.work(300)
        #expect(harness.snapshot.summary.longCompleted == 1)
        #expect(harness.completions(of: .long) == 0)
    }

    @Test("Prompt actions with nothing pending change nothing")
    func actionsWithoutAPendingPromptAreNoOps() {
        var harness = Harness()
        harness.work(600)
        let before = harness.snapshot

        harness.snooze()
        harness.skip()
        harness.endBreakEarly()

        #expect(harness.snapshot.summary == before.summary)
        #expect(harness.snapshot.shortRemaining == before.shortRemaining)
        #expect(harness.snapshot.longRemaining == before.longRemaining)
        #expect(harness.snapshot.activeBreak == nil)
    }

    @Test("Starting a second break while one runs is ignored")
    func startingASecondBreakIsIgnored() {
        var harness = Harness()
        harness.startBreak(.long)
        harness.work(10)
        harness.startBreak(.short)

        #expect(harness.snapshot.activeBreak?.kind == .long)
        #expect(harness.snapshot.activeBreak?.remaining == 890)
    }

    @Test("Resuming when not in quiet mode does nothing")
    func resumingWithoutQuietIsANoOp() {
        var harness = Harness()
        harness.work(1200)
        harness.resume()

        // No grace is granted, so the prompt that was already showing stays showing.
        #expect(harness.snapshot.pendingBreak == .short)
    }

    @Test("Nonsensical tick values cannot corrupt the schedules")
    func tickInputIsSanitised() {
        var harness = Harness()
        harness.engine.tick(now: harness.now, elapsed: .nan, unavailableElapsed: .nan, idleSeconds: .nan, isUnavailable: false)
        harness.engine.tick(now: harness.now, elapsed: -50, unavailableElapsed: -10, idleSeconds: -5, isUnavailable: false)
        // More unavailable time than elapsed time: clamped rather than trusted.
        harness.engine.tick(now: harness.now, elapsed: 10, unavailableElapsed: 10_000, idleSeconds: 0, isUnavailable: false)
        harness.engine.tick(now: harness.now, elapsed: .infinity, unavailableElapsed: 0, idleSeconds: 0, isUnavailable: false)

        #expect(harness.snapshot.shortRemaining <= 1200)
        #expect(harness.snapshot.shortRemaining >= 0)
        #expect(harness.snapshot.longRemaining <= 7200)
        #expect(harness.snapshot.longRemaining >= 0)
        #expect(harness.snapshot.activeBreak == nil)

        harness.work(1200)
        #expect(harness.snapshot.pendingBreak == .short)
    }
}
