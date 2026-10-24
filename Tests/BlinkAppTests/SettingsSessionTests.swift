import BlinkCore
import SwiftUI
import Testing
@testable import Blink

@Suite("Settings draft lifetime")
@MainActor
struct SettingsSessionTests {
    @Test("The window session retains invalid edits while changing pages")
    func draftSurvivesNavigation() {
        let session = AppWindowSession(settings: AppSettings())
        session.settings.draft.shortInterval = "not a number yet"
        session.settings.draft.settings.completionSoundEnabled = false
        session.selection = .today
        session.selection = .guide
        session.selection = .settings
        #expect(session.settings.draft.shortInterval == "not a number yet")
        #expect(!session.settings.draft.settings.completionSoundEnabled)
        #expect(session.settings.hasUnsavedChanges)
    }

    @Test("Saving establishes a new baseline and the next edit becomes unsaved")
    func savedBaseline() throws {
        let editor = SettingsEditor(settings: AppSettings())
        editor.draft.shortInterval = "30"
        editor.didSave(try editor.draft.validated())
        #expect(!editor.hasUnsavedChanges)
        #expect(editor.saved)
        // A delayed snapshot notification for this save must not erase Saved.
        editor.synchronize(try editor.draft.validated())
        #expect(editor.saved)
        let unchanged = editor.draft
        editor.draft = unchanged
        #expect(editor.saved)
        editor.draft.shortInterval = "31"
        #expect(editor.hasUnsavedChanges)
        #expect(!editor.saved)
    }

    @Test("External settings updates refresh clean drafts and preserve dirty drafts")
    func synchronizeWithoutDataLoss() {
        let editor = SettingsEditor(settings: AppSettings())
        var settings = AppSettings()
        settings.shortInterval = 1800
        editor.synchronize(settings)
        #expect(editor.draft.shortInterval == "30")
        #expect(!editor.hasUnsavedChanges)
        editor.draft.shortInterval = "unfinished"
        settings.shortInterval = 2400
        editor.synchronize(settings)
        #expect(editor.draft.shortInterval == "unfinished")
        #expect(editor.hasUnsavedChanges)
    }
}
