import Foundation
import Testing
@testable import BlinkCore

@Suite("Settings")
struct SettingsTests {
    @Test("Defaults match the published guidance")
    func defaultsMatchGuidance() {
        let settings = AppSettings()
        #expect(settings.shortInterval == 20 * 60)
        #expect(settings.shortDuration == 20)
        #expect(settings.longInterval == 120 * 60)
        #expect(settings.longDuration == 15 * 60)
        #expect(settings.blinkInterval == 60)
    }

    @Test("Zero, negative and non-finite timings are rejected, all at once")
    func invalidTimingsAreRejected() {
        var settings = AppSettings()
        settings.shortInterval = 0
        settings.longDuration = -1
        settings.blinkInterval = .nan

        #expect(throws: SettingsValidationError.self) { try settings.validated() }

        do {
            _ = try settings.validated()
            Issue.record("expected validation to fail")
        } catch let error as SettingsValidationError {
            #expect(Set(error.fields) == [.shortInterval, .longDuration, .blinkInterval])
            #expect(error.message(for: .shortInterval) == "Short break interval must be longer than zero.")
            #expect(error.message(for: .blinkInterval) == "Blink reminder interval must be a number.")
            #expect(error.message(for: .longInterval) == nil)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("Valid settings pass through unchanged")
    func validSettingsPass() throws {
        var settings = AppSettings()
        settings.shortInterval = 1
        let validated = try settings.validated()
        #expect(validated == settings)
    }

    @Test("Changing a timing restarts only the schedule it affects")
    func changingTimingRestartsOnlyThatSchedule() throws {
        var harness = Harness()
        harness.work(600)

        var settings = harness.snapshot.settings
        settings.shortInterval = 900
        try harness.updateSettings(settings)

        #expect(harness.snapshot.shortRemaining == 900)
        #expect(harness.snapshot.longRemaining == 7200 - 600)
    }

    @Test("Changing an unrelated setting preserves all progress")
    func unrelatedSettingPreservesProgress() throws {
        var harness = Harness()
        harness.work(600)

        var settings = harness.snapshot.settings
        settings.completionSoundEnabled = false
        try harness.updateSettings(settings)

        #expect(harness.snapshot.shortRemaining == 1200 - 600)
        #expect(harness.snapshot.longRemaining == 7200 - 600)
    }

    @Test("Disabling a break stops it becoming due and leaves the other running")
    func disablingABreakStopsIt() throws {
        var harness = Harness()
        var settings = harness.snapshot.settings
        settings.shortEnabled = false
        try harness.updateSettings(settings)

        harness.work(1200)
        #expect(harness.snapshot.pendingBreak == nil)
        #expect(harness.snapshot.longRemaining == 7200 - 1200)
    }

    @Test("Restoring recommended defaults never restarts onboarding")
    func restoringDefaultsKeepsOnboardingComplete() throws {
        var harness = Harness()
        harness.work(600)

        // The obvious implementation of the Restore button: hand back a fresh AppSettings,
        // whose onboardingComplete is false.
        try harness.updateSettings(AppSettings())

        #expect(harness.snapshot.settings.onboardingComplete)
        #expect(harness.snapshot.status == .running)

        harness.work(1200)
        #expect(harness.snapshot.pendingBreak == .short)
    }

    @Test("The convenience restore helper preserves onboarding too")
    func restoreHelperPreservesOnboarding() {
        var settings = AppSettings()
        settings.onboardingComplete = true
        settings.shortInterval = 99

        let restored = settings.restoringRecommendedDefaults()
        #expect(restored.shortInterval == 1200)
        #expect(restored.onboardingComplete)
    }

    @Test("Invalid settings are rejected without disturbing the engine")
    func invalidUpdateLeavesEngineUntouched() {
        var harness = Harness()
        harness.work(600)

        var settings = harness.snapshot.settings
        settings.shortInterval = 0
        #expect(throws: SettingsValidationError.self) { try harness.updateSettings(settings) }

        #expect(harness.snapshot.settings.shortInterval == 1200)
        #expect(harness.snapshot.shortRemaining == 1200 - 600)
    }

    @Test("Nothing is scheduled before onboarding finishes")
    func noSchedulingBeforeOnboarding() {
        var harness = Harness(onboarded: false)
        harness.work(2000)

        #expect(harness.snapshot.status == .onboarding)
        #expect(harness.snapshot.pendingBreak == nil)
        #expect(harness.blinkCount == 0)
        #expect(harness.snapshot.shortRemaining == 1200)

        harness.engine.completeOnboarding(now: harness.now)
        harness.work(1200)
        #expect(harness.snapshot.pendingBreak == .short)
    }
}
