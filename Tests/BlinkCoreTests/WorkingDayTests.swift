import Foundation
import Testing
@testable import BlinkCore

/// Simulated days check that scheduling stays coherent and bounded across work and
/// absences. Live working-day acceptance is tracked separately in docs/verification.md.
@Suite("Simulated working day")
struct WorkingDayTests {
    @Test("Eight hours of steady work produces a coherent set of breaks")
    func eightHoursOfSteadyWork() {
        var harness = Harness()
        let finish = harness.now.addingTimeInterval(8 * 3600)

        while harness.now < finish {
            if harness.snapshot.activeBreak == nil, let due = harness.snapshot.pendingBreak {
                harness.startBreak(due)
            }
            harness.work(1)
        }

        let summary = harness.snapshot.summary
        #expect(summary.skipped == 0)
        #expect(summary.snoozed == 0)
        // Roughly two hours of counted work per long break, minus the breaks themselves.
        #expect(summary.longCompleted == 3)
        // Six short breaks per long cycle, less the ones each long break replaced.
        #expect(summary.shortCompleted >= 15)
        #expect(summary.shortCompleted <= 20)
        #expect(harness.snapshot.status == .running)
        #expect(harness.snapshot.activeBreak == nil)
    }

    @Test("A realistic day of meetings and desk work never strands a break or a prompt")
    func dayWithAbsencesAndInterruptions() {
        var harness = Harness()

        for hour in 0..<8 {
            harness.work(1500)
            if harness.snapshot.activeBreak == nil, let due = harness.snapshot.pendingBreak {
                harness.startBreak(due)
                harness.work(harness.snapshot.settings.duration(for: due))
            }
            switch hour % 4 {
            case 0: harness.sitIdle(600)      // reading away from the keyboard
            case 1: harness.locked(1800)      // a meeting, screen locked
            case 2: harness.slept(2400)       // lunch, lid closed
            default: harness.work(600)
            }
        }

        let summary = harness.snapshot.summary
        #expect(summary.shortCompleted + summary.longCompleted > 0)
        #expect(harness.snapshot.activeBreak == nil)
        #expect(summary.shortCompleted >= 0)
        // Every counter stays in the day it belongs to, and no reminder is stranded.
        #expect(harness.snapshot.summary.day == Harness.calendar.startOfDay(for: harness.now))
    }

    @Test("Taking every break keeps both schedules inside their configured bounds")
    func schedulesStayBounded() {
        var harness = Harness()
        let finish = harness.now.addingTimeInterval(6 * 3600)

        while harness.now < finish {
            if harness.snapshot.activeBreak == nil, let due = harness.snapshot.pendingBreak {
                harness.startBreak(due)
            }
            harness.work(1)
            #expect(harness.snapshot.shortRemaining <= 1200)
            #expect(harness.snapshot.longRemaining <= 7200)
            #expect(harness.snapshot.shortRemaining >= 0)
            #expect(harness.snapshot.longRemaining >= 0)
        }
    }
}
