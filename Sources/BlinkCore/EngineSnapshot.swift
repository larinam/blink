import Foundation

/// What the app is currently doing, for the menu bar item.
public enum EngineStatus: String, Codable, CaseIterable, Sendable, Equatable {
    case running
    case quiet
    case idle
    case onBreak
    case onboarding
}

/// A break whose countdown is running.
public struct ActiveBreak: Codable, Equatable, Sendable {
    public let kind: BreakKind
    public let remaining: TimeInterval

    public init(kind: BreakKind, remaining: TimeInterval) {
        self.kind = kind
        self.remaining = remaining
    }
}

/// Everything the interface renders. Derived from engine state, never from effects, so a
/// dropped or repeated effect cannot desync the display.
///
/// `shortRemaining`, `longRemaining` and `movementRemaining` are in *counted screen time*, not wall time: they
/// stop advancing while the user is idle, away, or on a break. Display them only when the
/// corresponding settings flag is on.
public struct EngineSnapshot: Equatable, Sendable {
    public let settings: AppSettings
    public let summary: DailySummary
    public let status: EngineStatus
    public let shortRemaining: TimeInterval
    public let longRemaining: TimeInterval
    public let movementRemaining: TimeInterval
    /// The prompt to show, or nil. Already accounts for quiet, grace, idle and priority —
    /// present it whenever it is non-nil and hide it whenever it is nil.
    public let pendingBreak: BreakKind?
    public let activeBreak: ActiveBreak?
    public let isQuiet: Bool
    /// Expiry to display; nil while `isQuiet` means until manually resumed.
    public let quietUntil: Date?

    public init(
        settings: AppSettings,
        summary: DailySummary,
        status: EngineStatus,
        shortRemaining: TimeInterval,
        longRemaining: TimeInterval,
        movementRemaining: TimeInterval = 0,
        pendingBreak: BreakKind?,
        activeBreak: ActiveBreak?,
        isQuiet: Bool,
        quietUntil: Date?
    ) {
        self.settings = settings
        self.summary = summary
        self.status = status
        self.shortRemaining = shortRemaining
        self.longRemaining = longRemaining
        self.movementRemaining = movementRemaining
        self.pendingBreak = pendingBreak
        self.activeBreak = activeBreak
        self.isQuiet = isQuiet
        self.quietUntil = quietUntil
    }
}
