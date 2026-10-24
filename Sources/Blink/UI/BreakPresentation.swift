import BlinkCore
import Foundation

extension BreakKind {
    var title: String {
        switch self {
        case .short: "Eye break"
        case .movement: "Movement break"
        case .long: "Long break"
        }
    }

    var symbol: String {
        switch self {
        case .short: "sun.horizon"
        case .movement: "figure.stand"
        case .long: "leaf"
        }
    }

    var priority: Int {
        switch self {
        case .long: 0
        case .movement: 1
        case .short: 2
        }
    }
}

extension MovementActivity {
    var label: String {
        switch self {
        case .sitUps: "10 sit-ups"
        case .squats: "10 squats"
        case .walk: "A short walk"
        case .stretch: "Gentle stretching"
        case .rest: "Just step away"
        }
    }

    var promptTitle: String {
        switch self {
        case .sitUps: "Try 10 sit-ups."
        case .squats: "Try 10 squats."
        case .walk: "Take a little walk."
        case .stretch: "Make room to stretch."
        case .rest: "A little space for you."
        }
    }

    var instruction: String {
        switch self {
        case .sitUps: "Try 10 sit-ups, at your own pace."
        case .squats: "Try 10 squats, at your own pace."
        case .walk: "A short walk, at your own pace."
        case .stretch: "Gentle stretching, if comfortable."
        case .rest: "Simply step away from your screen."
        }
    }
}

extension EngineSnapshot {
    func remaining(for kind: BreakKind) -> Double {
        switch kind {
        case .short: shortRemaining
        case .movement: movementRemaining
        case .long: longRemaining
        }
    }

    var nextScheduledBreak: BreakKind? {
        BreakKind.allCases.filter { settings.isEnabled($0) }.min { first, second in
            let lhs = remaining(for: first), rhs = remaining(for: second)
            return lhs == rhs ? first.priority < second.priority : lhs < rhs
        }
    }
}

extension AppSettings {
    var movementStartTitle: String {
        let minutes = movementDuration / 60
        if minutes >= 1, minutes.rounded(.towardZero) == minutes {
            return "Start \(String(format: "%g", minutes))-minute break"
        }
        return "Start \(clockText(movementDuration)) break"
    }
}
