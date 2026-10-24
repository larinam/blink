import BlinkCore
import SwiftUI

struct SettingsDraft: Equatable {
    var settings: AppSettings
    var shortInterval: String
    var shortDuration: String
    var longInterval: String
    var longDuration: String
    var movementInterval: String
    var movementDuration: String
    var blinkInterval: String

    init(_ settings: AppSettings) {
        self.settings = settings
        shortInterval = String(format: "%g", settings.shortInterval / 60)
        shortDuration = String(format: "%g", settings.shortDuration)
        longInterval = String(format: "%g", settings.longInterval / 60)
        longDuration = String(format: "%g", settings.longDuration / 60)
        movementInterval = String(format: "%g", settings.movementInterval / 60)
        movementDuration = String(format: "%g", settings.movementDuration / 60)
        blinkInterval = String(format: "%g", settings.blinkInterval)
    }

    func validated() throws -> AppSettings {
        var result = settings
        func number(_ value: String, _ field: String) throws -> Double {
            guard let parsed = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)), parsed.isFinite, parsed > 0 else {
                throw DraftError(message: "\(field) must be a number greater than zero.")
            }
            return parsed
        }
        result.shortInterval = try number(shortInterval, "Eye break interval") * 60
        result.shortDuration = try number(shortDuration, "Eye break duration")
        result.longInterval = try number(longInterval, "Long break interval") * 60
        result.longDuration = try number(longDuration, "Long break duration") * 60
        result.movementInterval = try number(movementInterval, "Movement break interval") * 60
        result.movementDuration = try number(movementDuration, "Movement break duration") * 60
        result.blinkInterval = try number(blinkInterval, "Blink cue interval")
        return try result.validated()
    }
}

struct DraftError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var editor: SettingsEditor

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.needsStorageReset {
                        Card(padding: 17) {
                            VStack(alignment: .leading, spacing: 9) {
                                Label("Saved data needs attention", systemImage: "exclamationmark.triangle")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Your unreadable saved file is unchanged. Blink is using temporary defaults and cannot save changes until you explicitly reset that file.")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                                Button { model.resetUnreadableStorage() } label: {
                                    Text("Reset unreadable saved data").actionTarget()
                                }.buttonStyle(.bordered).controlSize(.large)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        SectionEyebrow(text: "Make it your rhythm")
                        Text("Gentle by default.").font(.system(size: 27, weight: .semibold, design: .rounded))
                        Text("Adjust the reminders to fit your day.").font(.system(size: 13)).foregroundStyle(.secondary)
                    }.padding(.bottom, 6)
                    Card(padding: 17) {
                        VStack(alignment: .leading, spacing: 15) {
                            reminderHeader("Eye breaks", subtitle: "A distant view, every so often.", enabled: $editor.draft.settings.shortEnabled, preview: { model.preview(.short) })
                            HStack(spacing: 20) {
                                timingField("Every", text: $editor.draft.shortInterval, unit: "minutes", label: "Eye break interval in minutes")
                                timingField("For", text: $editor.draft.shortDuration, unit: "seconds", label: "Eye break duration in seconds")
                            }.disabled(!editor.draft.settings.shortEnabled)
                            Text("Recommended: 20 minutes → 20 seconds, about 20 feet / 6 metres away.").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    Card(padding: 17) {
                        VStack(alignment: .leading, spacing: 15) {
                            reminderHeader("Movement breaks", subtitle: "A little time away to move.", enabled: $editor.draft.settings.movementEnabled,
                                           preview: { model.preview(.movement, settings: editor.draft.settings) })
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 20) {
                                    timingField("Every", text: $editor.draft.movementInterval, unit: "minutes", label: "Movement break interval in minutes")
                                    timingField("For", text: $editor.draft.movementDuration, unit: "minutes", label: "Movement break duration in minutes")
                                }
                                Text("Counts screen time. Pauses while you’re away or on a break.")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                                Divider()
                                Picker("My movement", selection: Binding(
                                    get: { editor.draft.settings.movementActivity.rawValue },
                                    set: { if let activity = MovementActivity(rawValue: $0) { editor.draft.settings.movementActivity = activity } }
                                )) {
                                    ForEach(MovementActivity.allCases, id: \.rawValue) { activity in
                                        Text(activity.label).tag(activity.rawValue)
                                    }
                                }.pickerStyle(.menu).controlSize(.large).frame(maxWidth: 330, alignment: .leading)
                                    .accessibilityLabel("Movement suggestion")
                                Text("Choose what feels comfortable. Repetitions aren’t tracked.")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }.disabled(!editor.draft.settings.movementEnabled)
                        }
                    }
                    Card(padding: 17) {
                        VStack(alignment: .leading, spacing: 15) {
                            reminderHeader("Long breaks", subtitle: "Leave your screens behind for a while.", enabled: $editor.draft.settings.longEnabled, preview: { model.preview(.long) })
                            HStack(spacing: 20) {
                                timingField("Every", text: $editor.draft.longInterval, unit: "minutes", label: "Long break interval in minutes")
                                timingField("For", text: $editor.draft.longDuration, unit: "minutes", label: "Long break duration in minutes")
                            }.disabled(!editor.draft.settings.longEnabled)
                            Text("Recommended: 120 minutes → at least 15 minutes away.").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    Card(padding: 17) {
                        VStack(alignment: .leading, spacing: 15) {
                            reminderHeader("Blink cues", subtitle: "A small, silent reminder to blink completely.", enabled: $editor.draft.settings.blinkEnabled, previewAllowed: model.snapshot.pendingBreak == nil, preview: { model.previewBlink() })
                            timingField("Every", text: $editor.draft.blinkInterval, unit: "seconds", label: "Blink cue interval in seconds")
                                .disabled(!editor.draft.settings.blinkEnabled)
                            Text("This is a reminder interval, not a prescribed blink rate.").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    Card(padding: 17) {
                        VStack(alignment: .leading, spacing: 17) {
                            Toggle(isOn: $editor.draft.settings.idleDetectionEnabled) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Notice when I’m away").font(.system(size: 13, weight: .medium))
                                    Text("Pause after 5 minutes without keyboard or pointer activity. Quiet reading can look like absence; turn this off when you prefer awake screen time.")
                                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                            }.accessibilityLabel("Notice when I’m away")
                                .accessibilityHint("Pause after five minutes of input inactivity. Turn off for quiet reading.")
                            Divider()
                            Toggle("Play a chime when a break finishes", isOn: $editor.draft.settings.completionSoundEnabled).font(.system(size: 13))
                            Divider()
                            Toggle("Launch Blink at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                                .font(.system(size: 13))
                            Text("Launch at login applies immediately. Reminder edits apply when you save.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            if model.loginNeedsApproval {
                                HStack {
                                    Text("Allow Blink in Login Items to finish enabling this.").font(.system(size: 11)).foregroundStyle(.secondary)
                                    Button { model.openLoginSettings() } label: {
                                        Text("Open System Settings").actionTarget()
                                    }.buttonStyle(.bordered).controlSize(.large)
                                }
                            }
                        }.toggleStyle(.switch).controlSize(.large)
                    }
                    Text("Settings and today’s summary stay on this Mac. No camera, microphone, screen recording, account, or telemetry.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                    Text(model.globalShortcutAvailable
                        ? "Open Blink from any app with \(model.globalShortcutDescription.label)."
                        : "The \(model.globalShortcutDescription.label) shortcut is unavailable. Open Blink using its menu bar icon.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                        .accessibilityLabel(model.globalShortcutAvailable
                            ? "Open Blink from any app with \(model.globalShortcutDescription.spoken)."
                            : "The \(model.globalShortcutDescription.spoken) shortcut is unavailable. Open Blink using its menu bar icon.")
                }
                .padding(.horizontal, 26).padding(.top, 26).padding(.bottom, 20)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    Button {
                        if model.saveSettings(AppSettings()) {
                            editor.didSave(model.snapshot.settings)
                        }
                    } label: { Text("Restore recommended defaults").actionTarget() }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button(action: save) { Text("Save settings").actionTarget() }
                        .buttonStyle(.borderedProminent).keyboardShortcut("s", modifiers: .command)
                }.controlSize(.large).font(.system(size: 12))
                Text(editor.saved ? "Saved" : editor.hasUnsavedChanges
                     ? "Unsaved changes · kept until Blink quits."
                     : "Timing changes restart affected timers.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.horizontal, 26).padding(.vertical, 17)
        }
        .onChange(of: model.snapshot.settings) { _, settings in editor.synchronize(settings) }
    }

    private func reminderHeader(_ title: String, subtitle: String, enabled: Binding<Bool>, previewAllowed: Bool = true, preview: @escaping () -> Void) -> some View {
        HStack(alignment: .center) {
            Toggle(isOn: enabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.toggleStyle(.switch).controlSize(.large).accessibilityLabel(title)
                .accessibilityHint(subtitle)
            Button(action: preview) { Text("Preview").actionTarget() }.buttonStyle(.bordered).controlSize(.large)
                .accessibilityLabel("Preview \(title.lowercased())")
                .disabled(model.snapshot.activeBreak != nil || !previewAllowed)
        }
    }

    private func timingField(_ title: String, text: Binding<String>, unit: String, label: String) -> some View {
        HStack(spacing: 7) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            TextField("", text: text).textFieldStyle(.roundedBorder).controlSize(.large).frame(width: 72)
                .multilineTextAlignment(.trailing).accessibilityLabel(label)
            Text(unit).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private func save() {
        do {
            if model.saveSettings(try editor.draft.validated()) { editor.didSave(model.snapshot.settings) }
        } catch { model.errorMessage = error.localizedDescription }
    }
}

struct SidebarNavigation: View {
    @Binding var selection: AppPage
    @State private var hoveredPage: AppPage?
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(AppPage.allCases) { page in
                Button { selection = page } label: {
                    Label(page.rawValue, systemImage: page.symbol).font(.system(size: 12, weight: selection == page ? .semibold : .regular))
                        .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .background(selection == page ? BlinkStyle.accent.opacity(0.10) : .primary.opacity(hoveredPage == page ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 9))
                        .foregroundStyle(selection == page ? BlinkStyle.accent : .primary)
                        .contentShape(.interaction, RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain)
                .onHover { hovering in hoveredPage = hovering ? page : nil }
                .accessibilityAddTraits(selection == page ? [.isSelected] : [])
            }
        }
    }
}

struct AppWindowView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var session: AppWindowSession

    init(model: AppModel, session: AppWindowSession) {
        self.model = model
        self.session = session
    }

    init(model: AppModel, selection: AppPage) {
        self.init(model: model, session: AppWindowSession(settings: model.snapshot.settings, selection: selection))
    }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 9) {
                    EyeMark(size: 33)
                    Text("Blink").font(.system(size: 21, weight: .semibold, design: .rounded))
                }.padding(.bottom, 30).padding(.top, 12)
                SidebarNavigation(selection: $session.selection)
                Spacer()
                Text("A little space\nbetween screens.").font(.system(size: 11)).foregroundStyle(.tertiary).lineSpacing(3).padding(.leading, 7)
            }.padding(17).frame(width: 170)
            Divider()
            Group {
                switch session.selection {
                case .settings: SettingsView(model: model, editor: session.settings)
                case .today: TodayView(model: model).padding(28)
                case .guide: ScrollView { ScreenGuide().padding(28) }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 850, minHeight: 680)
        .background(BlinkStyle.canvas).tint(BlinkStyle.accent)
        .alert("Blink", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            ScrollView { ScreenGuide().padding(30) }
            Divider()
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Ready when you are.").font(.system(size: 13, weight: .medium))
                    Text("Reminders begin after you start. Find Blink in your menu bar.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.finishOnboarding() } label: { Text("Start using Blink").actionTarget() }
                    .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.return, modifiers: [])
            }.padding(25)
        }
        .frame(width: 650, height: 705).background(BlinkStyle.canvas).tint(BlinkStyle.accent)
        .alert("Blink", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}
