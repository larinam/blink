import Foundation
import Testing
@testable import BlinkCore

/// R4. The engine decides only *whether* and *when*; the display and the drawing are the
/// adapter's, and nothing here measures or claims to verify a blink.
@Suite("Blink cues")
struct BlinkCueTests {
    @Test("A cue arrives every 60 counted seconds")
    func cueEveryMinute() {
        var harness = Harness()
        harness.work(60)
        #expect(harness.blinkCount == 1)

        harness.work(59)
        #expect(harness.blinkCount == 1)

        harness.work(1)
        #expect(harness.blinkCount == 2)
    }

    @Test("Cues are suppressed while a break prompt is waiting")
    func suppressedByPendingPrompt() {
        var harness = Harness()
        harness.work(1200)
        let before = harness.blinkCount

        harness.work(300)
        #expect(harness.snapshot.pendingBreak == .short)
        #expect(harness.blinkCount == before)
    }

    @Test("Cues are suppressed during a break and discarded, not queued")
    func suppressedDuringBreak() {
        var harness = Harness()
        harness.work(1200)
        harness.startBreak(.long)
        _ = harness.drain()

        harness.work(900)
        #expect(harness.blinkCount == 0)

        // The fifteen suppressed cues do not arrive on the other side.
        harness.work(59)
        #expect(harness.blinkCount == 0)
        harness.work(1)
        #expect(harness.blinkCount == 1)
    }

    @Test("Cues are suppressed while idle")
    func suppressedWhileIdle() {
        var harness = Harness()
        harness.work(30)
        _ = harness.drain()

        harness.sitIdle(600)
        // Cues before the idle threshold are legitimate; none once the absence is detected.
        let duringThreshold = harness.blinkCount
        _ = harness.drain()
        harness.sitIdle(600)
        #expect(harness.blinkCount == 0)
        #expect(duringThreshold <= 5)
    }

    @Test("No cue fires the instant the user returns from an absence")
    func noCueImmediatelyOnReturn() {
        var harness = Harness()
        harness.work(59)
        harness.sitIdle(600)
        _ = harness.drain()

        harness.work(30)
        #expect(harness.blinkCount == 0)
        harness.work(30)
        #expect(harness.blinkCount == 1)
    }

    @Test("Cues can be disabled without affecting breaks")
    func cuesDisableIndependently() {
        var settings = AppSettings()
        settings.blinkEnabled = false
        var harness = Harness(settings: settings)

        harness.work(1200)
        #expect(harness.blinkCount == 0)
        #expect(harness.snapshot.pendingBreak == .short)
    }

    @Test("The cue interval is configurable")
    func cueIntervalIsConfigurable() throws {
        var harness = Harness()
        var settings = harness.snapshot.settings
        settings.blinkInterval = 20
        try harness.updateSettings(settings)
        _ = harness.drain()

        harness.work(60)
        #expect(harness.blinkCount == 3)
    }
}
