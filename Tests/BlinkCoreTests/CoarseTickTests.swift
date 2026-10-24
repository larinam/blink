import Foundation
import Testing
@testable import BlinkCore

/// The engine promises the adapter that a coalesced timer changes the resolution of a
/// countdown but never its outcome. These tests hold it to that across a break boundary,
/// where a single tick has to both retire the break and account for the time after it.
@Suite("Coarse ticks")
struct CoarseTickTests {
    @Test("Time after a break completes inside one tick is still counted")
    func leftoverAfterCompletionIsCounted() {
        var harness = Harness()
        harness.startBreak(.short)
        // One 60-second tick: 20 seconds finish the break, 40 are screen time.
        harness.tick(step: 60)

        #expect(harness.snapshot.activeBreak == nil)
        #expect(harness.snapshot.summary.shortCompleted == 1)
        #expect(harness.snapshot.shortRemaining == 1200 - 40)
        #expect(harness.snapshot.longRemaining == 7200 - 40)
    }

    @Test("One coarse tick lands where many fine ticks do")
    func coarseAndFineTicksAgree() {
        var coarse = Harness()
        coarse.startBreak(.long)
        coarse.tick(step: 1500)

        var fine = Harness()
        fine.startBreak(.long)
        fine.work(1500)

        #expect(coarse.snapshot.shortRemaining == fine.snapshot.shortRemaining)
        #expect(coarse.snapshot.longRemaining == fine.snapshot.longRemaining)
        #expect(coarse.snapshot.summary == fine.snapshot.summary)
        #expect(coarse.snapshot.activeBreak == fine.snapshot.activeBreak)
        // 900 seconds of break then 600 of work, however the ticks were sliced.
        #expect(coarse.snapshot.longRemaining == 7200 - 600)
    }

    @Test("A tick ending exactly on completion leaves nothing over")
    func completionExactlyAtWindowEnd() {
        var harness = Harness()
        harness.startBreak(.short)
        harness.tick(step: 20)

        #expect(harness.snapshot.activeBreak == nil)
        #expect(harness.snapshot.summary.shortCompleted == 1)
        #expect(harness.snapshot.shortRemaining == 1200)
        #expect(harness.snapshot.longRemaining == 7200)
    }

    @Test("Unavailable time in a break-completing tick is not counted as screen time")
    func leftoverUnavailableTimeIsNotCounted() {
        var harness = Harness()
        harness.startBreak(.short)
        // The whole hour was asleep: 20 seconds of it finished the break, and the rest is
        // an absence, not 3580 seconds at the keyboard.
        harness.slept(3600)

        #expect(harness.snapshot.summary.shortCompleted == 1)
        #expect(harness.completions(of: .short) == 0)
        #expect(harness.snapshot.shortRemaining == 1200)
        #expect(harness.snapshot.longRemaining == 7200)
    }

    @Test("A blink cue can still fire in the remainder of a break-completing tick")
    func leftoverCanProduceACue() {
        var harness = Harness()
        harness.startBreak(.short)
        _ = harness.drain()
        // 20 seconds of break, then 60 seconds of screen time — one cue's worth.
        harness.tick(step: 80)

        #expect(harness.snapshot.summary.shortCompleted == 1)
        #expect(harness.blinkCount == 1)
    }

    @Test("A break due in the remainder of a break-completing tick is not lost")
    func leftoverCanMakeTheNextBreakDue() {
        var harness = Harness(settings: .fast(short: 60, long: 6000, blink: 600))
        harness.work(60)
        harness.startBreak(.short)
        // 5 seconds of break, then 60 more seconds of work: the next short break is due.
        harness.tick(step: 65)

        #expect(harness.snapshot.summary.shortCompleted == 1)
        #expect(harness.snapshot.pendingBreak == .short)
    }

    @Test("Only one break can retire per tick, however coarse")
    func oneBreakPerTick() {
        var harness = Harness(settings: .fast(short: 10, long: 6000, blink: 600))
        harness.work(10)
        harness.startBreak(.short)
        // A full hour in one tick: the break retires once, and the time after it accrues
        // normally rather than cascading through further breaks.
        harness.tick(step: 3600)

        #expect(harness.snapshot.summary.shortCompleted == 1)
        #expect(harness.snapshot.activeBreak == nil)
        #expect(harness.snapshot.pendingBreak == .short)
    }

    @Test("A restored break completes on new elapsed time, not the time the app was closed")
    func restoredBreakCompletesOnFreshTime() throws {
        var harness = Harness()
        harness.startBreak(.long)
        harness.work(892)

        let data = try JSONEncoder().encode(harness.engine.state)
        let restored = try JSONDecoder().decode(EngineState.self, from: data)
        var relaunched = Harness(resuming: restored, at: harness.now.addingTimeInterval(86_400))

        #expect(relaunched.snapshot.activeBreak?.remaining == 8)
        relaunched.tick(step: 8)
        #expect(relaunched.snapshot.summary.longCompleted == 1)
        #expect(relaunched.completions(of: .long) == 1)
    }
}
