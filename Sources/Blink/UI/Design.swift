import AppKit
import SwiftUI

enum BlinkStyle {
    static let accent = adaptive(light: (0.16, 0.39, 0.31), dark: (0.60, 0.82, 0.68))
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let muted = Color.secondary
    static let corner: CGFloat = 18

    /// An sRGB color that resolves per appearance: deep enough for light backgrounds, soft enough for dark.
    static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }
}

struct EyeMark: View {
    var size: CGFloat = 44
    var body: some View {
        Image(systemName: "eye")
            .font(.system(size: size * 0.47, weight: .medium))
            .foregroundStyle(BlinkStyle.accent)
            .frame(width: size, height: size)
            .background(BlinkStyle.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: BlinkStyle.corner))
            .overlay(RoundedRectangle(cornerRadius: BlinkStyle.corner).stroke(.primary.opacity(0.07), lineWidth: 1))
    }
}

struct SectionEyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(1.4).foregroundStyle(.secondary)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            .padding(.horizontal, 17).padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(BlinkStyle.accent.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 11))
            .contentShape(.interaction, RoundedRectangle(cornerRadius: 11))
    }
}

extension View {
    /// Apply inside a native button's label, so its padding participates in clicks.
    /// On macOS 26, the large native bezel makes this a measured 44-point target.
    func actionTarget(expands: Bool = false) -> some View {
        frame(minWidth: 28, maxWidth: expands ? .infinity : nil, minHeight: 32)
            .contentShape(.interaction, Rectangle())
    }
}

func clockText(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite else { return "—" }
    let value = Int(min(max(ceil(seconds), 0), 31_536_000))
    if value >= 3600 { return String(format: "%dh %02dm", value / 3600, value % 3600 / 60) }
    return String(format: "%02d:%02d", value / 60, value % 60)
}

struct GuidanceRow: View {
    let number: String
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Text(number).font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(BlinkStyle.accent)
                .frame(width: 29, height: 29)
                .background(BlinkStyle.accent.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ScreenGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                EyeMark()
                VStack(alignment: .leading, spacing: 4) {
                    SectionEyebrow(text: "Make room for rest")
                    Text("A little kinder to your eyes.").font(.system(size: 24, weight: .semibold, design: .rounded))
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 22) {
                    GuidanceRow(number: "01", title: "Find a distant view", detail: "Every 20 minutes, look at something about 20 feet / 6 metres away for 20 seconds. Choose a view beyond your screen before you begin.")
                    GuidanceRow(number: "02", title: "Lower the screen centre", detail: "Position the centre of your screen about 4–5 inches / 10–13 cm below eye level, at a comfortable distance of 20–28 inches / 50–70 cm. Adjust lighting to reduce uncomfortable glare.")
                    GuidanceRow(number: "03", title: "Blink completely", detail: "Gently close and open your eyes fully and deliberately. Blink cues are reminders to notice the habit; their interval is not a prescribed blink rate.")
                    GuidanceRow(number: "04", title: "Take a longer pause", detail: "After two hours of screen time, step away from screens for at least 15 minutes. Give yourself space to move and rest.")
                    GuidanceRow(number: "05", title: "Make room to move", detail: "Optional movement breaks give you a little time away each hour. Choose a comfortable activity in Settings, such as 10 squats, a short walk, or gentle stretching. The activity and time away are your preferences; Blink doesn’t count repetitions.")
                }
            }
            Text("These habits support eye comfort. The 20-20-20 rule is a guideline, not a cure-all for digital eye strain. Blink does not measure your eyes, posture, or whether you looked away.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Link(destination: URL(string: "https://www.aoa.org/healthy-eyes/eye-and-vision-conditions/computer-vision-syndrome")!) {
                    Text("Eye care guidance ↗").actionTarget()
                }
                Link(destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/24413278/")!) {
                    Text("About complete blinking ↗").actionTarget()
                }
            }.font(.system(size: 12)).buttonStyle(.bordered).controlSize(.large).tint(BlinkStyle.accent)
        }
    }
}
