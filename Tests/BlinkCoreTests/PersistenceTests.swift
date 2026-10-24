import Foundation
import Testing
@testable import BlinkCore

/// Acceptance check 5: relaunch and midnight.
@Suite("Persistence and day boundaries")
struct PersistenceTests {
    private func roundTrip(_ state: EngineState) throws -> EngineState {
        let data = try JSONEncoder().encode(state)
        return try JSONDecoder().decode(EngineState.self, from: data)
    }

    @Test("Settings, counters and schedule progress survive a relaunch")
    func progressSurvivesRelaunch() throws {
        var harness = Harness()
        harness.work(1000)
        harness.startBreak(.short)
        harness.work(20)
        harness.work(500)

        let restored = try roundTrip(harness.engine.state)
        var relaunched = Harness(resuming: restored, at: harness.now.addingTimeInterval(7200))

        #expect(relaunched.snapshot.summary.shortCompleted == 1)
        relaunched.work(1)
        // The two closed-off hours count for nothing; the 500 seconds before them remain.
        #expect(relaunched.snapshot.shortRemaining == 1200 - 501)
        #expect(relaunched.snapshot.longRemaining == 7200 - 1501)
    }

    @Test("A break running at quit resumes with the remaining time it had")
    func activeBreakResumesWithSavedRemaining() throws {
        var harness = Harness()
        harness.startBreak(.long)
        harness.work(892)
        #expect(harness.snapshot.activeBreak?.remaining == 8)

        let restored = try roundTrip(harness.engine.state)
        var relaunched = Harness(resuming: restored, at: harness.now.addingTimeInterval(3600))

        // The hour the app was closed is not credited against the countdown.
        #expect(relaunched.snapshot.activeBreak?.remaining == 8)
        #expect(relaunched.snapshot.summary.longCompleted == 0)

        relaunched.work(7)
        #expect(relaunched.snapshot.activeBreak?.remaining == 1)
        relaunched.work(1)
        #expect(relaunched.snapshot.activeBreak == nil)
        #expect(relaunched.snapshot.summary.longCompleted == 1)
    }

    @Test("Quiet mode that expired while the app was closed is not still running")
    func expiredQuietDoesNotSurviveRelaunch() throws {
        var harness = Harness()
        harness.setQuiet(minutes: 15)
        let restored = try roundTrip(harness.engine.state)

        let relaunched = Harness(resuming: restored, at: harness.now.addingTimeInterval(3600))
        #expect(!relaunched.snapshot.isQuiet)
    }

    @Test("Indefinite quiet mode does survive a relaunch")
    func indefiniteQuietSurvivesRelaunch() throws {
        var harness = Harness()
        harness.setQuiet(minutes: nil)
        let restored = try roundTrip(harness.engine.state)

        let relaunched = Harness(resuming: restored, at: harness.now.addingTimeInterval(3600))
        #expect(relaunched.snapshot.isQuiet)
        #expect(relaunched.snapshot.quietUntil == nil)
    }

    @Test("Nothing is presented in the first seconds after launch")
    func launchDoesNotFlashAnOverduePrompt() throws {
        var harness = Harness()
        harness.work(1200)
        let restored = try roundTrip(harness.engine.state)

        var relaunched = Harness(resuming: restored, at: harness.now.addingTimeInterval(60))
        #expect(relaunched.snapshot.pendingBreak == nil)

        relaunched.work(9)
        #expect(relaunched.snapshot.pendingBreak == nil)
        relaunched.work(1)
        #expect(relaunched.snapshot.pendingBreak == .short)
    }

    @Test("Midnight resets today's counters without disturbing the schedules")
    func midnightResetsCountersOnly() {
        var harness = Harness(start: Harness.date(year: 2026, month: 9, day: 10, hour: 23, minute: 30))
        harness.work(1000)
        harness.startBreak(.short)
        harness.work(20)
        harness.skip()
        #expect(harness.snapshot.summary.shortCompleted == 1)

        harness.work(1800)
        #expect(harness.snapshot.summary.shortCompleted == 0)
        #expect(harness.snapshot.summary.skipped == 0)
        #expect(harness.snapshot.summary.day == Harness.date(year: 2026, month: 9, day: 11))
        // 1000 seconds before the break plus 1800 after it, with the break itself free.
        #expect(harness.snapshot.longRemaining == 7200 - 2800)
    }

    @Test("A break that ran out before midnight is not counted as completed today")
    func completionBeforeMidnightIsNotCountedToday() {
        var harness = Harness(start: Harness.date(year: 2026, month: 9, day: 10, hour: 23, minute: 0))
        harness.startBreak(.long)
        harness.work(60)
        // The Mac sleeps at 23:01 and wakes at 08:00; the timer ran out at 23:15.
        harness.slept(9 * 3600)

        #expect(harness.snapshot.activeBreak == nil)
        #expect(harness.snapshot.summary.day == Harness.date(year: 2026, month: 9, day: 11))
        #expect(harness.snapshot.summary.longCompleted == 0)
        #expect(harness.completions(of: .long) == 0)
        // The rest was still taken, so the schedules are reset.
        #expect(harness.snapshot.longRemaining == 7200)
        #expect(harness.snapshot.shortRemaining == 1200)
    }

    @Test("Persisted state stays small: no history accumulates")
    func stateDoesNotGrow() throws {
        var harness = Harness()
        let encoder = JSONEncoder()

        func size(after cycles: Int) throws -> Int {
            for _ in 0..<cycles {
                harness.work(1200)
                harness.startBreak(.short)
                harness.work(20)
            }
            return try encoder.encode(harness.engine.state).count
        }

        let early = try size(after: 20)
        let late = try size(after: 2000)

        // A hundred times as many breaks costs a couple of bytes of decimal width. Any
        // per-break record would be orders of magnitude larger than this.
        #expect(late - early < 16)
        #expect(late < 1024)
        // The run spans several simulated days, so the counters roll over rather than
        // climbing forever — which is the other half of retaining no history.
        #expect(harness.snapshot.summary.day == Harness.calendar.startOfDay(for: harness.now))
    }
}
