import AppKit
import BlinkCore
import Testing
@testable import Blink

@Suite("Movement presentation")
struct MovementPresentationTests {
    @Test("Next-break summary respects disabled schedules and tie priority")
    func nextBreakSelection() {
        var settings = AppSettings()
        settings.movementEnabled = true
        #expect(snapshot(settings, short: 60, movement: 60, long: 60).nextScheduledBreak == .long)
        #expect(snapshot(settings, short: 60, movement: 60, long: 120).nextScheduledBreak == .movement)
        #expect(snapshot(settings, short: 30, movement: 60, long: 120).nextScheduledBreak == .short)
        settings.movementEnabled = false
        #expect(snapshot(settings, short: 60, movement: 0, long: 120).nextScheduledBreak == .short)
        settings.shortEnabled = false
        settings.longEnabled = false
        #expect(snapshot(settings, short: 0, movement: 0, long: 0).nextScheduledBreak == nil)
    }

    @Test("Every break kind has an available native symbol")
    @MainActor
    func symbolsExist() {
        for kind in BreakKind.allCases {
            #expect(NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil) != nil)
        }
    }

    private func snapshot(_ settings: AppSettings, short: Double, movement: Double, long: Double) -> EngineSnapshot {
        EngineSnapshot(settings: settings, summary: DailySummary(), status: .running,
                       shortRemaining: short, longRemaining: long, movementRemaining: movement,
                       pendingBreak: nil, activeBreak: nil, isQuiet: false, quietUntil: nil)
    }
}
