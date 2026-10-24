import Foundation
import Testing
@testable import BlinkCore

/// Scheduling regressions for delayed snooze actions, sleep-time completion and
/// quiet-expiry grace on coalesced ticks.
@Suite("Review regressions")
struct ReviewRegressionTests {
    @Test("Snoozing a prompt that sat unanswered defers it a full five minutes", arguments: [BreakKind.short, .long, .movement])
    func snoozeAnchorsToTheAction(kind: BreakKind) {
        var settings = AppSettings()
        // Isolate the kind under test so other schedules cannot interfere.
        switch kind {
        case .short: settings.longEnabled = false
        case .long: settings.shortEnabled = false
        case .movement:
            settings.shortEnabled = false
            settings.longEnabled = false
            settings.movementEnabled = true
        }
        var harness = Harness(settings: settings)

        harness.work(settings.interval(for: kind))
        #expect(harness.snapshot.pendingBreak == kind)

        // The user ignores it for ten minutes, then presses Snooze.
        harness.work(600)
        harness.snooze()

        #expect(harness.snapshot.pendingBreak == nil)
        harness.work(299)
        #expect(harness.snapshot.pendingBreak == nil)
        harness.work(1)
        #expect(harness.snapshot.pendingBreak == kind)
    }

    @Test("A break that ran out during sleep does not chime on wake")
    func noChimeReplayedOnWake() {
        var harness = Harness()
        harness.startBreak(.short)
        // No ticks at all while suspended: the adapter reports the whole hour on wake.
        harness.slept(3600)

        #expect(harness.snapshot.summary.shortCompleted == 1)
        #expect(harness.completions(of: .short) == 0)
        #expect(harness.snapshot.activeBreak == nil)

        harness.work(300)
        #expect(harness.completions(of: .short) == 0)
    }

    @Test("A break that ran out while awake still chimes on the same tick")
    func chimeStillFiresWhenAwake() {
        var harness = Harness()
        harness.startBreak(.short)
        harness.work(20)

        #expect(harness.completions(of: .short) == 1)
    }

    @Test("A break outlasting a short sleep chimes once the Mac is awake again")
    func chimeFiresWhenTimerOutlastsTheSleep() {
        var harness = Harness()
        harness.startBreak(.long)
        harness.work(60)
        // A minute of work and a minute of sleep leave 780 seconds of the 900-second break.
        harness.slept(60)
        #expect(harness.completions(of: .long) == 0)
        #expect(harness.snapshot.activeBreak?.remaining == 780)

        harness.work(780)
        #expect(harness.completions(of: .long) == 1)
    }

    @Test("Quiet expiring on a long delayed tick still grants the full ten seconds")
    func quietExpiryGraceSurvivesADelayedTick() {
        var harness = Harness()
        harness.work(1200)
        #expect(harness.snapshot.pendingBreak == .short)

        harness.setQuiet(minutes: 15)
        #expect(harness.snapshot.pendingBreak == nil)

        // A single coalesced tick covering the entire quiet period lands on expiry.
        harness.tick(step: 900)
        #expect(!harness.snapshot.isQuiet)
        #expect(harness.snapshot.pendingBreak == nil)

        harness.work(9)
        #expect(harness.snapshot.pendingBreak == nil)
        harness.work(1)
        #expect(harness.snapshot.pendingBreak == .short)
    }

    @Test("Quiet expiring on an ordinary tick grants the same ten seconds")
    func quietExpiryGraceOnANormalTick() {
        var harness = Harness()
        harness.work(1200)
        harness.setQuiet(minutes: 15)

        harness.work(900)
        #expect(!harness.snapshot.isQuiet)
        #expect(harness.snapshot.pendingBreak == nil)

        harness.work(9)
        #expect(harness.snapshot.pendingBreak == nil)
        harness.work(1)
        #expect(harness.snapshot.pendingBreak == .short)
    }
}
