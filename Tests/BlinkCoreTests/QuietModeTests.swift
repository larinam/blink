import Foundation
import Testing
@testable import BlinkCore

/// Acceptance check 6.
@Suite("Quiet mode")
struct QuietModeTests {
    @Test("Quiet mode hides every reminder while eligible screen time keeps accumulating")
    func quietSuppressesRemindersButNotCounting() {
        var harness = Harness()
        harness.setQuiet(minutes: nil)
        harness.work(1200)

        #expect(harness.snapshot.isQuiet)
        #expect(harness.snapshot.quietUntil == nil)
        #expect(harness.snapshot.status == .quiet)
        #expect(harness.snapshot.pendingBreak == nil)
        #expect(harness.blinkCount == 0)
        // Eligible time accumulated throughout: the short break is due the moment it ends.
        #expect(harness.snapshot.shortRemaining == 0)
    }

    @Test("Resuming produces one overdue prompt after ten seconds, not a burst")
    func resumingDoesNotReplayABacklog() {
        var harness = Harness()
        harness.setQuiet(minutes: nil)
        harness.work(3600)
        harness.resume()
        _ = harness.drain()

        harness.work(9)
        #expect(harness.snapshot.pendingBreak == nil)
        #expect(harness.blinkCount == 0)

        harness.work(1)
        #expect(harness.snapshot.pendingBreak == .short)

        // An hour of suppressed minute-cues does not arrive at once.
        harness.work(50)
        #expect(harness.blinkCount == 0)
    }

    @Test("A timed quiet period expires on wall time")
    func quietExpiresOnWallTime() {
        var harness = Harness()
        harness.setQuiet(minutes: 15)
        #expect(harness.snapshot.quietUntil != nil)

        harness.work(899)
        #expect(harness.snapshot.isQuiet)

        harness.work(1)
        #expect(!harness.snapshot.isQuiet)
        #expect(harness.snapshot.quietUntil == nil)
    }

    @Test("Quiet time passing while the Mac is asleep still expires the quiet period")
    func quietExpiresAcrossSleep() {
        var harness = Harness()
        harness.setQuiet(minutes: 30)
        harness.slept(3600)

        #expect(!harness.snapshot.isQuiet)
    }

    @Test("Starting quiet mode during a break ends it rather than hiding it")
    func quietEndsAnActiveBreak() {
        var harness = Harness()
        harness.work(1200)
        harness.startBreak(.short)
        harness.work(5)
        harness.setQuiet(minutes: nil)

        #expect(harness.snapshot.activeBreak == nil)
        #expect(harness.snapshot.summary.skipped == 1)
        #expect(harness.snapshot.summary.shortCompleted == 0)
        #expect(harness.snapshot.status == .quiet)
    }

    @Test("Quiet mode does not stack its grace or replay it")
    func graceDoesNotStack() {
        var harness = Harness()
        harness.work(1200)
        harness.setQuiet(minutes: nil)
        harness.resume()
        harness.setQuiet(minutes: nil)
        harness.resume()

        harness.work(9)
        #expect(harness.snapshot.pendingBreak == nil)
        harness.work(1)
        #expect(harness.snapshot.pendingBreak == .short)
    }
}
