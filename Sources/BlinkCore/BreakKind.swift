import Foundation

/// The guided break kinds. Blink cues are not breaks and are not represented here.
public enum BreakKind: String, Codable, CaseIterable, Sendable, Equatable {
    case short
    case long
    /// A short time away from the screen to move, separate from the long rest.
    case movement
}

/// What the user plans to do during a movement break. Presentation only: the engine never
/// counts repetitions, and the choice does not affect scheduling. Raw values are persisted.
public enum MovementActivity: String, Codable, CaseIterable, Sendable, Equatable {
    case sitUps
    case squats
    case walk
    case stretch
    case rest
}
