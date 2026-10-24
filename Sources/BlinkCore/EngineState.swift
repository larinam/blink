import Foundation

/// Fixed rules from the requirements. Not user-configurable.
enum SchedulingConstants {
    /// Input inactivity that counts as an idle absence.
    static let idleThreshold: TimeInterval = 300
    /// Observed lock/sleep long enough to reset the short schedule.
    static let unavailableShortReset: TimeInterval = 20
    /// Absence long enough to reset the movement schedule: the user was already away.
    static let movementReset: TimeInterval = 300
    /// Absence long enough to reset every break schedule.
    static let bothReset: TimeInterval = 900
    /// Counted screen time a snooze defers an occurrence by.
    static let snoozeCredit: TimeInterval = 300
    /// Settling time before an overdue prompt appears after quiet or inactivity ends.
    static let resumeGrace: TimeInterval = 10
}

/// Progress toward one occurrence, measured in counted screen time.
///
/// `target` is normally the configured interval; snooze sets it to `accrued` plus
/// 300 seconds, preserving accrued time for the idle rollback.
struct Schedule: Codable, Equatable, Sendable {
    var accrued: TimeInterval
    var target: TimeInterval

    init(target: TimeInterval) {
        self.accrued = 0
        self.target = target
    }

    var remaining: TimeInterval { max(0, target - accrued) }
    var isDue: Bool { accrued >= target }

    mutating func restart(interval: TimeInterval) {
        accrued = 0
        target = interval
    }

    /// Removes already-counted time, never below zero — which is what stops a rollback
    /// reaching across a completed break, a schedule reset or a relaunch.
    mutating func rollBack(_ amount: TimeInterval) {
        accrued = max(0, accrued - max(0, amount))
    }

    /// Makes a decoded schedule meaningful again. A non-finite `target` is the dangerous
    /// case: every comparison against it is false, so the occurrence would never come due
    /// and reminders would stop for good without anything reporting a fault.
    mutating func repair(interval: TimeInterval) {
        if !target.isFinite || target <= 0 { target = interval }
        if !accrued.isFinite || accrued < 0 { accrued = 0 }
    }
}

/// A contiguous stretch during which counted screen time does not accrue, because the
/// Mac was unavailable, the user was idle, or both.
struct Absence: Codable, Equatable, Sendable {
    var unavailableSeconds: TimeInterval = 0
    var totalSeconds: TimeInterval = 0
    var idleDetected: Bool = false
    var didResetShort: Bool = false
    var didResetMovement: Bool = false
    var didResetBoth: Bool = false

    init() {}

    private enum CodingKeys: String, CodingKey {
        case unavailableSeconds, totalSeconds, idleDetected, didResetShort, didResetMovement, didResetBoth
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        unavailableSeconds = try container.decode(TimeInterval.self, forKey: .unavailableSeconds)
        totalSeconds = try container.decode(TimeInterval.self, forKey: .totalSeconds)
        idleDetected = try container.decode(Bool.self, forKey: .idleDetected)
        didResetShort = try container.decode(Bool.self, forKey: .didResetShort)
        didResetMovement = try container.decodeIfPresent(Bool.self, forKey: .didResetMovement) ?? false
        didResetBoth = try container.decode(Bool.self, forKey: .didResetBoth)
    }
}

/// The whole persistable value. Opaque to the adapter, which stores and restores the
/// encoded bytes without interpreting or constructing the fields.
public struct EngineState: Codable, Equatable, Sendable {
    var settings: AppSettings
    var summary: DailySummary
    var short: Schedule
    var long: Schedule
    var movement: Schedule
    var blink: Schedule
    /// A break that has become due and is awaiting the user, retained across quiet
    /// periods and absences so it can be presented once, never replayed as a backlog.
    var dueBreak: BreakKind?
    var activeBreak: ActiveBreak?
    var quietActive: Bool
    var quietUntil: Date?
    var graceRemaining: TimeInterval
    var absence: Absence?
    /// Counted screen time accrued since the user last touched the keyboard or pointer.
    /// Bounds the retroactive idle rollback so time the engine never credited — a sleep
    /// span, for instance — is not removed a second time.
    var countedSinceLastInput: TimeInterval

    /// Repairs state that decoded but cannot be true, so a corrupted or hand-edited file
    /// degrades to sane scheduling rather than to silence. Every rule here is chosen so
    /// that legitimate state is left untouched.
    mutating func normalize(now: Date, calendar: Calendar) {
        settings = settings.repaired()
        short.repair(interval: settings.shortInterval)
        long.repair(interval: settings.longInterval)
        movement.repair(interval: settings.movementInterval)
        blink.repair(interval: settings.blinkInterval)

        // A non-finite grace never decays past zero, which would suppress every reminder
        // forever; an oversized one would suppress them for as long as it lasted.
        if !graceRemaining.isFinite || graceRemaining < 0 { graceRemaining = 0 }
        graceRemaining = min(graceRemaining, SchedulingConstants.resumeGrace)

        if let active = activeBreak {
            let duration = settings.duration(for: active.kind)
            if !active.remaining.isFinite || active.remaining <= 0 {
                // Not a completion: an unusable countdown is discarded, not credited.
                activeBreak = nil
            } else if active.remaining > duration {
                // Bound the overlay: a break can never legitimately outlast its own length.
                activeBreak = ActiveBreak(kind: active.kind, remaining: duration)
            }
        }

        if let until = quietUntil, !until.timeIntervalSinceReferenceDate.isFinite { quietUntil = nil }
        // An expiry with no quiet period would show a stale "quiet until" in the menu bar.
        if !quietActive { quietUntil = nil }

        // A summary dated in the future would never roll over, so today's counters would
        // never reset.
        if !summary.day.timeIntervalSinceReferenceDate.isFinite || summary.day > now {
            summary = DailySummary(now: now, calendar: calendar)
        } else {
            summary.day = calendar.startOfDay(for: summary.day)
            summary.shortCompleted = max(0, summary.shortCompleted)
            summary.longCompleted = max(0, summary.longCompleted)
            summary.movementCompleted = max(0, summary.movementCompleted)
            summary.skipped = max(0, summary.skipped)
            summary.snoozed = max(0, summary.snoozed)
        }

        // An owed occurrence always has its schedule at or past target: between becoming due
        // and any idle rollback, accrual grows by at least what the rollback removes, since
        // the rollback is bounded by the counted time since the last input. So a `dueBreak`
        // whose schedule is not due cannot have been earned, and a prompt for a disabled
        // break could never be cleared by the schedules at all.
        if let due = dueBreak, !settings.isEnabled(due) || !schedule(for: due).isDue {
            dueBreak = nil
        }

        if !countedSinceLastInput.isFinite || countedSinceLastInput < 0 { countedSinceLastInput = 0 }
        if var current = absence {
            if !current.unavailableSeconds.isFinite || current.unavailableSeconds < 0 { current.unavailableSeconds = 0 }
            if !current.totalSeconds.isFinite || current.totalSeconds < 0 { current.totalSeconds = 0 }
            absence = current
        }
    }

    func schedule(for kind: BreakKind) -> Schedule {
        switch kind {
        case .short: short
        case .long: long
        case .movement: movement
        }
    }

    public init(now: Date = Date(), calendar: Calendar = .current) {
        let settings = AppSettings()
        self.settings = settings
        self.summary = DailySummary(now: now, calendar: calendar)
        self.short = Schedule(target: settings.shortInterval)
        self.long = Schedule(target: settings.longInterval)
        self.movement = Schedule(target: settings.movementInterval)
        self.blink = Schedule(target: settings.blinkInterval)
        self.dueBreak = nil
        self.activeBreak = nil
        self.quietActive = false
        self.quietUntil = nil
        self.graceRemaining = 0
        self.absence = nil
        self.countedSinceLastInput = 0
    }

    private enum CodingKeys: String, CodingKey {
        case settings, summary, short, long, movement, blink, dueBreak, activeBreak
        case quietActive, quietUntil, graceRemaining, absence, countedSinceLastInput
    }

    /// A missing movement schedule starts a fresh interval for saved-state compatibility.
    /// Other non-optional fields remain required.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        settings = try container.decode(AppSettings.self, forKey: .settings)
        summary = try container.decode(DailySummary.self, forKey: .summary)
        short = try container.decode(Schedule.self, forKey: .short)
        long = try container.decode(Schedule.self, forKey: .long)
        movement = try container.decodeIfPresent(Schedule.self, forKey: .movement)
            ?? Schedule(target: settings.movementInterval)
        blink = try container.decode(Schedule.self, forKey: .blink)
        dueBreak = try container.decodeIfPresent(BreakKind.self, forKey: .dueBreak)
        activeBreak = try container.decodeIfPresent(ActiveBreak.self, forKey: .activeBreak)
        quietActive = try container.decode(Bool.self, forKey: .quietActive)
        quietUntil = try container.decodeIfPresent(Date.self, forKey: .quietUntil)
        graceRemaining = try container.decode(TimeInterval.self, forKey: .graceRemaining)
        absence = try container.decodeIfPresent(Absence.self, forKey: .absence)
        countedSinceLastInput = try container.decode(TimeInterval.self, forKey: .countedSinceLastInput)
    }
}
