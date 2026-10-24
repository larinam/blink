import Foundation

/// Today's counters. No history is retained: the summary is replaced at local midnight.
///
/// "Completed" means a break timer finished. It is never a claim that gaze, blinking or
/// actual rest was verified.
public struct DailySummary: Codable, Equatable, Sendable {
    /// Start of the local day these counters belong to.
    public var day: Date
    /// Guided short breaks whose timer ran to completion.
    public var shortCompleted: Int
    /// Guided long breaks whose timer ran to completion.
    public var longCompleted: Int
    /// Guided movement breaks whose timer ran to completion. Repetitions are never counted.
    public var movementCompleted: Int
    /// Prompts dismissed with Skip, plus started breaks ended early.
    public var skipped: Int
    /// Snooze actions, counted individually.
    public var snoozed: Int

    public init(now: Date = Date(), calendar: Calendar = .current) {
        self.day = calendar.startOfDay(for: now)
        self.shortCompleted = 0
        self.longCompleted = 0
        self.skipped = 0
        self.snoozed = 0
        self.movementCompleted = 0
    }

    public init(
        day: Date, shortCompleted: Int = 0, longCompleted: Int = 0, skipped: Int = 0, snoozed: Int = 0,
        movementCompleted: Int = 0
    ) {
        self.day = day
        self.shortCompleted = shortCompleted
        self.longCompleted = longCompleted
        self.skipped = skipped
        self.snoozed = snoozed
        self.movementCompleted = movementCompleted
    }

    private enum CodingKeys: String, CodingKey {
        case day, shortCompleted, longCompleted, skipped, snoozed, movementCompleted
    }

    /// A missing movement counter defaults to zero for saved-state compatibility.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            day: try container.decode(Date.self, forKey: .day),
            shortCompleted: try container.decode(Int.self, forKey: .shortCompleted),
            longCompleted: try container.decode(Int.self, forKey: .longCompleted),
            skipped: try container.decode(Int.self, forKey: .skipped),
            snoozed: try container.decode(Int.self, forKey: .snoozed),
            movementCompleted: try container.decodeIfPresent(Int.self, forKey: .movementCompleted) ?? 0
        )
    }

    public func covers(_ now: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(day, inSameDayAs: now)
    }

    public mutating func recordCompletion(of kind: BreakKind) {
        switch kind {
        case .short: shortCompleted += 1
        case .long: longCompleted += 1
        case .movement: movementCompleted += 1
        }
    }
}
