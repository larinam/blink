import BlinkCore
import SwiftUI

enum AppPage: String, CaseIterable, Identifiable {
    case settings = "Settings"
    case today = "Today"
    case guide = "Screen setup"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .settings: "slider.horizontal.3"
        case .today: "chart.bar.xaxis"
        case .guide: "display"
        }
    }
}

struct MenuView: View {
    @ObservedObject var model: AppModel
    let openPage: (AppPage) -> Void
    let close: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 11) {
                EyeMark(size: 39)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Blink").font(.system(size: 19, weight: .semibold, design: .rounded))
                    Text(statusText).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(model.snapshot.isQuiet ? Color.orange : BlinkStyle.accent).frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            }

            if !model.snapshot.settings.onboardingComplete {
                Text("A few small habits for more comfortable screen time.").font(.system(size: 13)).foregroundStyle(.secondary)
                Button("Set up Blink") { openPage(.guide) }.buttonStyle(PrimaryButtonStyle())
            } else if let active = model.snapshot.activeBreak {
                Card(padding: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        SectionEyebrow(text: active.kind.title + " in progress")
                        Text(clockText(active.remaining)).font(.system(size: 32, weight: .light, design: .rounded)).monospacedDigit()
                        Button { model.endBreak(); close() } label: {
                            Text("End break").actionTarget(expands: true)
                        }.buttonStyle(.bordered).controlSize(.large)
                    }
                }
            } else {
                if model.snapshot.pendingBreak == nil, let next = model.snapshot.nextScheduledBreak {
                    Card(padding: 13) {
                        VStack(alignment: .leading, spacing: 5) {
                            SectionEyebrow(text: "Next · " + next.title.lowercased())
                            Text(clockText(model.snapshot.remaining(for: next)))
                                .font(.system(size: 25, weight: .medium, design: .rounded)).monospacedDigit()
                            Text(breakHint(next)).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
                Card(padding: 13) {
                    VStack(spacing: 9) {
                        countdownRow(.short)
                        Divider()
                        countdownRow(.movement)
                        Divider()
                        countdownRow(.long)
                    }
                }
                if let pending = model.snapshot.pendingBreak, !model.snapshot.isQuiet, model.snapshot.status != .idle {
                    Text("Your \(pending.title.lowercased()) is ready.")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(BlinkStyle.accent)
                    Button("Start break") { model.startBreak(pending); close() }.buttonStyle(PrimaryButtonStyle())
                    HStack(spacing: 10) {
                        Button { model.snooze() } label: { Text("Snooze 5 minutes").actionTarget(expands: true) }
                        Button { model.skip() } label: { Text("Skip").actionTarget(expands: true) }
                    }.buttonStyle(.bordered).controlSize(.large)
                } else {
                    Button { model.startBreak(.short); close() } label: {
                        Label("Rest your eyes now", systemImage: "sun.horizon")
                    }.buttonStyle(PrimaryButtonStyle())
                    Button { model.startBreak(.movement); close() } label: {
                        Label("Move now", systemImage: "figure.stand").actionTarget(expands: true)
                    }.buttonStyle(.bordered).controlSize(.large)
                        .disabled(!model.snapshot.settings.movementEnabled)
                    Button { model.startBreak(.long); close() } label: {
                        Label("Start a long break", systemImage: "leaf").actionTarget(expands: true)
                    }.buttonStyle(.bordered).controlSize(.large)
                }

                if model.snapshot.isQuiet {
                    HStack {
                        Image(systemName: "moon").foregroundStyle(.secondary)
                        Text(quietDescription).font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Button { model.resume() } label: { Text("Resume").actionTarget() }
                            .buttonStyle(.bordered).controlSize(.large)
                    }
                } else {
                    HStack(spacing: 8) {
                        Text("Quiet for").font(.system(size: 11)).foregroundStyle(.secondary)
                        ForEach([15, 30, 60], id: \.self) { minutes in
                            Button { model.quiet(minutes: minutes) } label: { Text("\(minutes)m").actionTarget() }
                                .buttonStyle(.bordered).controlSize(.large)
                                .accessibilityLabel("Quiet for \(minutes) minutes")
                        }
                        Button { model.quiet(minutes: nil) } label: {
                            Image(systemName: "infinity").actionTarget()
                        }.buttonStyle(.bordered).controlSize(.large)
                            .accessibilityLabel("Quiet until I resume")
                            .help("Quiet until you resume")
                    }
                }
            }

            Divider()
            HStack(spacing: 10) {
                Button { openPage(.today) } label: { Label("Today", systemImage: "chart.bar.xaxis").actionTarget() }
                Button { openPage(.settings) } label: { Label("Settings", systemImage: "slider.horizontal.3").actionTarget() }
                Spacer()
                Button(action: quit) { Text("Quit").actionTarget() }
            }.buttonStyle(.bordered).controlSize(.large).font(.system(size: 12))
        }
        .padding(21).frame(width: 368)
        .background(BlinkStyle.canvas).tint(BlinkStyle.accent)
    }

    private func countdownRow(_ kind: BreakKind) -> some View {
        let enabled = model.snapshot.settings.isEnabled(kind)
        let value = model.snapshot.remaining(for: kind)
        return HStack(spacing: 10) {
            Image(systemName: kind.symbol).font(.system(size: 17))
                .foregroundStyle(enabled ? BlinkStyle.accent : .secondary).frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(kind == .movement ? "Movement" : kind.title).font(.system(size: 12, weight: .medium))
                Text(breakHint(kind)).font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Text(enabled ? (value <= 0 ? "Ready" : clockText(value)) : "Off")
                .font(.system(size: 17, weight: .medium, design: .rounded)).monospacedDigit()
                .foregroundStyle(enabled && value <= 0 ? BlinkStyle.accent : enabled ? .primary : .secondary)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    private func breakHint(_ kind: BreakKind) -> String {
        switch kind {
        case .short: "\(clockText(model.snapshot.settings.shortDuration)) of distant focus"
        case .movement: "\(clockText(model.snapshot.settings.movementDuration)) away · \(model.snapshot.settings.movementActivity.label.lowercased())"
        case .long: "\(clockText(model.snapshot.settings.longDuration)) away from screens"
        }
    }

    private var statusText: String {
        switch model.snapshot.status {
        case .running: "A little space between screens."
        case .quiet: "Quiet mode · screen time still counts"
        case .idle: "Away · timers paused"
        case .onBreak: "Take your time."
        case .onboarding: "Welcome. Let’s make room for rest."
        }
    }

    private var quietDescription: String {
        if let date = model.snapshot.quietUntil { return "Quiet until \(date.formatted(date: .omitted, time: .shortened))" }
        return "Quiet until you resume"
    }
}

struct TodayView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                SectionEyebrow(text: Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                Text("Small pauses add up.").font(.system(size: 27, weight: .semibold, design: .rounded))
                Text("Your guided breaks today, on this Mac.").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                summaryCard(value: model.snapshot.summary.shortCompleted, title: "Eye breaks", icon: "sun.horizon")
                summaryCard(value: model.snapshot.summary.movementCompleted, title: "Movement breaks", icon: "figure.stand")
                summaryCard(value: model.snapshot.summary.longCompleted, title: "Long breaks", icon: "leaf")
            }
            Card {
                HStack {
                    Label("Skipped or ended early", systemImage: "forward.end")
                    Spacer()
                    Text("\(model.snapshot.summary.skipped)").monospacedDigit().fontWeight(.semibold)
                }.font(.system(size: 13))
                Divider().padding(.vertical, 9)
                HStack {
                    Label("Snooze actions", systemImage: "clock.arrow.circlepath")
                    Spacer()
                    Text("\(model.snapshot.summary.snoozed)").monospacedDigit().fontWeight(.semibold)
                }.font(.system(size: 13))
            }
            Text("Completed means the break timer finished. Blink doesn’t verify that you looked away, moved, or rested, and doesn’t count repetitions. Time naturally spent away adjusts your schedule without adding a guided break.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield").foregroundStyle(BlinkStyle.accent)
                Text("Only today is kept. Your counters reset at local midnight, and your data stays on this Mac. No account, camera, or cloud.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
            }
            Spacer(minLength: 0)
        }
    }

    private func summaryCard(value: Int, title: String, icon: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 15) {
                Image(systemName: icon).font(.system(size: 22, weight: .light)).foregroundStyle(BlinkStyle.accent).accessibilityHidden(true)
                Text("\(value)").font(.system(size: 46, weight: .light, design: .rounded)).monospacedDigit()
                Text(title + " completed").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine)
    }
}
