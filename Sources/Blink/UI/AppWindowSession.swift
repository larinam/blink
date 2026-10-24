import BlinkCore
import Combine

/// Owned by the application window, rather than a conditional SwiftUI page, so
/// even invalid text survives navigation and closing/reopening that window.
@MainActor
final class SettingsEditor: ObservableObject {
    @Published var draft: SettingsDraft {
        didSet { if draft != oldValue { saved = false } }
    }
    @Published private(set) var saved = false
    private var baseline: SettingsDraft

    var hasUnsavedChanges: Bool { draft != baseline }

    init(settings: AppSettings) {
        let draft = SettingsDraft(settings)
        self.draft = draft
        baseline = draft
    }

    func didSave(_ settings: AppSettings) {
        baseline = SettingsDraft(settings)
        draft = baseline
        saved = true
    }

    func synchronize(_ settings: AppSettings) {
        let updated = SettingsDraft(settings)
        guard !hasUnsavedChanges, updated != baseline else { return }
        baseline = updated
        draft = baseline
    }
}

@MainActor
final class AppWindowSession: ObservableObject {
    @Published var selection: AppPage
    let settings: SettingsEditor

    init(settings: AppSettings, selection: AppPage = .settings) {
        self.settings = SettingsEditor(settings: settings)
        self.selection = selection
    }
}
