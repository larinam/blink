import SwiftUI

enum BlinkCueTiming {
    static let duration = 3.0
    static let fadeIn = 0.22
    static let fadeOut = 0.28
    static let fadeOutStart = duration - fadeOut
}

/// One eyelid keyframe: the openness (1 open, 0 closed) reached at the end of `duration`.
struct EyelidStep: Equatable {
    var openness: Double
    var duration: TimeInterval
}

/// A once-a-minute cue that never changes stops being seen. Each variant pairs its wording
/// with a matching eye motion and tint, so the cue differs in what it asks, not just how it looks.
/// Every motion starts and ends open and finishes before the fade, keeping one 3-second cue.
enum BlinkCueVariant: CaseIterable {
    case fully, twoSlow, closeBriefly, soft

    var title: String {
        switch self {
        case .fully: "Blink fully"
        case .twoSlow: "Two slow blinks"
        case .closeBriefly: "Close your eyes"
        case .soft: "Blink softly"
        }
    }

    var detail: String {
        switch self {
        case .fully: "and deliberately."
        case .twoSlow: "all the way closed."
        case .closeBriefly: "for a moment."
        case .soft: "and relax your face."
        }
    }

    var steps: [EyelidStep] {
        // The leading open step is the settle before the first close.
        switch self {
        case .fully:
            [.init(openness: 1, duration: 0.45), .init(openness: 0, duration: 0.18),
             .init(openness: 0, duration: 0.12), .init(openness: 1, duration: 0.28)]
        case .twoSlow:
            [.init(openness: 1, duration: 0.45), .init(openness: 0, duration: 0.24),
             .init(openness: 0, duration: 0.14), .init(openness: 1, duration: 0.32),
             .init(openness: 1, duration: 0.22), .init(openness: 0, duration: 0.24),
             .init(openness: 0, duration: 0.14), .init(openness: 1, duration: 0.32)]
        case .closeBriefly:
            [.init(openness: 1, duration: 0.45), .init(openness: 0, duration: 0.30),
             .init(openness: 0, duration: 0.70), .init(openness: 1, duration: 0.40)]
        case .soft:
            [.init(openness: 1, duration: 0.45), .init(openness: 0, duration: 0.26),
             .init(openness: 0, duration: 0.10), .init(openness: 1, duration: 0.38)]
        }
    }

    var tint: Color {
        switch self {
        case .fully: BlinkStyle.accent
        case .twoSlow: BlinkStyle.adaptive(light: (0.07, 0.36, 0.44), dark: (0.53, 0.80, 0.86))
        case .closeBriefly: BlinkStyle.adaptive(light: (0.29, 0.30, 0.62), dark: (0.69, 0.71, 0.96))
        case .soft: BlinkStyle.adaptive(light: (0.58, 0.31, 0.08), dark: (0.96, 0.73, 0.50))
        }
    }
}

/// Hands out variants in shuffled rounds: each variant once per round and never the same one
/// twice in a row, including across a round boundary.
struct BlinkCueSequence {
    private var pending: [BlinkCueVariant] = []
    private var last: BlinkCueVariant?
    private let shuffle: (inout [BlinkCueVariant]) -> Void

    init(shuffle: @escaping (inout [BlinkCueVariant]) -> Void = { $0.shuffle() }) {
        self.shuffle = shuffle
    }

    mutating func next() -> BlinkCueVariant {
        if pending.isEmpty {
            var round = BlinkCueVariant.allCases
            shuffle(&round)
            // Variants are taken from the end.
            if round.count > 1, round.last == last { round.swapAt(0, round.count - 1) }
            pending = round
        }
        let variant = pending.removeLast()
        last = variant
        return variant
    }
}

struct BlinkCueView: View {
    static let size = CGSize(width: 232, height: 64)
    static let insets = EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
    var variant: BlinkCueVariant
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        BlinkCueCard(variant: variant, reduceMotion: reduceMotion, contrast: contrast)
    }
}

/// The presentation accepts appearance inputs so native renders can also inspect
/// Increased Contrast without changing the user's system accessibility settings.
struct BlinkCueCard: View {
    var variant: BlinkCueVariant
    var reduceMotion: Bool
    var contrast: ColorSchemeContrast

    var body: some View {
        BlinkCueLabel(variant: variant, reduceMotion: reduceMotion, contrast: contrast)
            .padding(BlinkCueView.insets)
            .frame(width: BlinkCueView.size.width, height: BlinkCueView.size.height, alignment: .leading)
            .background(BlinkStyle.canvas, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.primary.opacity(contrast == .increased ? 1 : 0.06)))
            .accessibilityElement(children: .combine)
    }
}

/// The eye and instruction at their natural size; the card's fixed frame must contain it.
struct BlinkCueLabel: View {
    var variant: BlinkCueVariant
    var reduceMotion: Bool
    var contrast: ColorSchemeContrast

    var body: some View {
        HStack(spacing: 12) {
            AnimatedBlinkEye(reduceMotion: reduceMotion, steps: variant.steps)
                .foregroundStyle(contrast == .increased ? Color.primary : variant.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(variant.title)
                    .font(.title2.weight(.semibold))
                Text(variant.detail)
                    .font(.body)
            }
            // Both lines are essential parts of the same instruction.
            .foregroundStyle(Color.primary)
            .fixedSize()
        }
    }
}

struct AnimatedBlinkEye: View {
    var reduceMotion: Bool
    var steps: [EyelidStep] = BlinkCueVariant.fully.steps
    @State private var started = false
    @State private var motionSuppressed = false

    var body: some View {
        KeyframeAnimator(initialValue: 1.0, trigger: started) { openness in
            BlinkEyeGlyph(openness: reduceMotion || motionSuppressed ? 1 : openness)
        } keyframes: { _ in
            KeyframeTrack(\.self) {
                for step in steps {
                    LinearKeyframe(step.openness, duration: step.duration, timingCurve: .easeInOut)
                }
            }
        }
        .onAppear { if !reduceMotion { started = true } }
        .onChange(of: reduceMotion) { _, enabled in
            // Enabling Reduce Motion stops the blink immediately. Toggling back
            // does not jump into a partly completed blink; the next cue can animate.
            if enabled { motionSuppressed = true }
        }
    }
}

struct BlinkEyeGlyph: View {
    var openness: Double

    var body: some View {
        ZStack {
            Circle().frame(width: 11, height: 11)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(EyelidAperture(openness: openness))
            EyelidAperture(openness: openness)
                .stroke(style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 38, height: 28)
    }
}

private struct EyelidAperture: Shape {
    // KeyframeAnimator supplies each interpolated value; this shape does not
    // add a second implicit animation between those frames.
    var openness: Double

    func path(in rect: CGRect) -> Path {
        let amount = min(1, max(0, openness))
        let left = CGPoint(x: rect.minX + 1, y: rect.midY)
        let right = CGPoint(x: rect.maxX - 1, y: rect.midY)
        let height = rect.height * 0.78 * amount
        var path = Path()
        path.move(to: left)
        path.addQuadCurve(to: right, control: CGPoint(x: rect.midX, y: rect.midY - height))
        path.addQuadCurve(to: left, control: CGPoint(x: rect.midX, y: rect.midY + height))
        path.closeSubpath()
        return path
    }
}
