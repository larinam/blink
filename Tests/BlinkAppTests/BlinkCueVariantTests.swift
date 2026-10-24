import AppKit
import SwiftUI
import Testing
@testable import Blink

@Suite("Blink cue variants")
struct BlinkCueVariantTests {
    @Test("Every eye motion blinks fully, ends open, and finishes before the fade", arguments: BlinkCueVariant.allCases)
    func motionFitsTheCue(_ variant: BlinkCueVariant) {
        let steps = variant.steps
        #expect(steps.allSatisfy { $0.duration > 0 })
        #expect(steps.first?.openness == 1)
        #expect(steps.last?.openness == 1)
        #expect(steps.contains { $0.openness == 0 })
        // Leave the eye visibly open for a beat before the panel starts to fade.
        #expect(steps.map(\.duration).reduce(0, +) <= BlinkCueTiming.fadeOutStart - 0.4)
    }

    @Test("Wording differs between variants")
    func distinctWording() {
        let titles = Set(BlinkCueVariant.allCases.map(\.title))
        #expect(titles.count == BlinkCueVariant.allCases.count)
    }

    @Test("Each round shows every variant once, with no repeat across rounds")
    func shuffledRounds() {
        var sequence = BlinkCueSequence()
        let count = BlinkCueVariant.allCases.count
        let drawn = (0..<count * 50).map { _ in sequence.next() }
        for start in stride(from: 0, to: drawn.count, by: count) {
            #expect(Set(drawn[start..<start + count]) == Set(BlinkCueVariant.allCases))
        }
        #expect(zip(drawn, drawn.dropFirst()).allSatisfy { $0 != $1 })
    }

    @Test("A round that would start with the previous variant is reordered")
    func roundBoundary() {
        // Alternating orders make every second round start with the variant that ended the previous one.
        var reversed = false
        var sequence = BlinkCueSequence { round in
            if reversed { round.reverse() }
            reversed.toggle()
        }
        let count = BlinkCueVariant.allCases.count
        let drawn = (0..<count * 4).map { _ in sequence.next() }
        #expect(drawn[count - 1] == BlinkCueVariant.allCases.first)
        #expect(drawn[count] != drawn[count - 1])
        #expect(zip(drawn, drawn.dropFirst()).allSatisfy { $0 != $1 })
        #expect(Set(drawn[count..<count * 2]) == Set(BlinkCueVariant.allCases))
    }

    @Test("Each variant's eye and wording fit inside the fixed card", arguments: BlinkCueVariant.allCases)
    @MainActor
    func labelFits(_ variant: BlinkCueVariant) {
        let insets = BlinkCueView.insets
        let available = CGSize(width: BlinkCueView.size.width - insets.leading - insets.trailing,
                               height: BlinkCueView.size.height - insets.top - insets.bottom)
        for contrast in [ColorSchemeContrast.standard, .increased] {
            let label = NSHostingView(rootView: BlinkCueLabel(variant: variant, reduceMotion: true, contrast: contrast))
            let size = label.fittingSize
            #expect(size.width <= available.width && size.height <= available.height,
                    "\(variant) needs \(size), card offers \(available)")
        }
    }
}
