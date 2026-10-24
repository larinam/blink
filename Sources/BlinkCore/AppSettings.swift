import Foundation

/// User-facing preferences. Every timing value is in seconds.
///
/// Defaults follow AOA guidance: a 20-second look-away after 20 minutes, and a
/// 15-minute break after 120 minutes. They are supportive habits, not treatment.
///
/// Movement breaks default to two minutes away from the screen each hour and remain
/// disabled until the user enables them.
public struct AppSettings: Codable, Equatable, Sendable {
    public var shortEnabled: Bool
    public var shortInterval: TimeInterval
    public var shortDuration: TimeInterval

    public var longEnabled: Bool
    public var longInterval: TimeInterval
    public var longDuration: TimeInterval

    public var blinkEnabled: Bool
    public var blinkInterval: TimeInterval

    public var idleDetectionEnabled: Bool
    public var completionSoundEnabled: Bool

    public var movementEnabled: Bool
    public var movementInterval: TimeInterval
    public var movementDuration: TimeInterval
    public var movementActivity: MovementActivity

    /// Lifecycle state, not a preference: "Restore recommended defaults" must not
    /// clear it. `updateSettings` preserves the existing value and ignores the
    /// incoming one. See docs/decisions.md (D6).
    public var onboardingComplete: Bool

    public init() {
        self.init(
            shortEnabled: true, shortInterval: 1200, shortDuration: 20,
            longEnabled: true, longInterval: 7200, longDuration: 900,
            blinkEnabled: true, blinkInterval: 60,
            idleDetectionEnabled: true, completionSoundEnabled: true,
            onboardingComplete: false,
            movementEnabled: false, movementInterval: 3600, movementDuration: 120,
            movementActivity: .squats
        )
    }

    public init(
        shortEnabled: Bool = true,
        shortInterval: TimeInterval = 1200,
        shortDuration: TimeInterval = 20,
        longEnabled: Bool = true,
        longInterval: TimeInterval = 7200,
        longDuration: TimeInterval = 900,
        blinkEnabled: Bool = true,
        blinkInterval: TimeInterval = 60,
        idleDetectionEnabled: Bool = true,
        completionSoundEnabled: Bool = true,
        onboardingComplete: Bool = false,
        movementEnabled: Bool = false,
        movementInterval: TimeInterval = 3600,
        movementDuration: TimeInterval = 120,
        movementActivity: MovementActivity = .squats
    ) {
        self.shortEnabled = shortEnabled
        self.shortInterval = shortInterval
        self.shortDuration = shortDuration
        self.longEnabled = longEnabled
        self.longInterval = longInterval
        self.longDuration = longDuration
        self.blinkEnabled = blinkEnabled
        self.blinkInterval = blinkInterval
        self.idleDetectionEnabled = idleDetectionEnabled
        self.completionSoundEnabled = completionSoundEnabled
        self.onboardingComplete = onboardingComplete
        self.movementEnabled = movementEnabled
        self.movementInterval = movementInterval
        self.movementDuration = movementDuration
        self.movementActivity = movementActivity
    }

    private enum CodingKeys: String, CodingKey {
        case shortEnabled, shortInterval, shortDuration
        case longEnabled, longInterval, longDuration
        case blinkEnabled, blinkInterval
        case idleDetectionEnabled, completionSoundEnabled, onboardingComplete
        case movementEnabled, movementInterval, movementDuration, movementActivity
    }

    /// Missing movement fields use the recommended defaults for saved-state compatibility;
    /// a missing enablement flag leaves movement disabled. All other fields are required
    /// so incomplete settings report a decode failure rather than silently reverting.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        self.init(
            shortEnabled: try container.decode(Bool.self, forKey: .shortEnabled),
            shortInterval: try container.decode(TimeInterval.self, forKey: .shortInterval),
            shortDuration: try container.decode(TimeInterval.self, forKey: .shortDuration),
            longEnabled: try container.decode(Bool.self, forKey: .longEnabled),
            longInterval: try container.decode(TimeInterval.self, forKey: .longInterval),
            longDuration: try container.decode(TimeInterval.self, forKey: .longDuration),
            blinkEnabled: try container.decode(Bool.self, forKey: .blinkEnabled),
            blinkInterval: try container.decode(TimeInterval.self, forKey: .blinkInterval),
            idleDetectionEnabled: try container.decode(Bool.self, forKey: .idleDetectionEnabled),
            completionSoundEnabled: try container.decode(Bool.self, forKey: .completionSoundEnabled),
            onboardingComplete: try container.decode(Bool.self, forKey: .onboardingComplete),
            movementEnabled: try container.decodeIfPresent(Bool.self, forKey: .movementEnabled) ?? defaults.movementEnabled,
            movementInterval: try container.decodeIfPresent(TimeInterval.self, forKey: .movementInterval) ?? defaults.movementInterval,
            movementDuration: try container.decodeIfPresent(TimeInterval.self, forKey: .movementDuration) ?? defaults.movementDuration,
            movementActivity: try container.decodeIfPresent(MovementActivity.self, forKey: .movementActivity) ?? defaults.movementActivity
        )
    }

    /// The recommended defaults offered by "Restore recommended defaults".
    ///
    /// Onboarding completion is deliberately preserved: restoring defaults is a
    /// settings action, and it must never send a returning user back through onboarding.
    public func restoringRecommendedDefaults() -> AppSettings {
        var defaults = AppSettings()
        defaults.onboardingComplete = onboardingComplete
        return defaults
    }

    /// Returns the settings unchanged, or throws describing every invalid field at once.
    ///
    /// Only zero, negative and nonfinite timings are rejected. No cross-field rules are
    /// imposed — the requirements do not ask for them, and inventing limits would surprise
    /// a user who deliberately wants, say, a 30-second break every 10 minutes.
    @discardableResult
    public func validated() throws -> AppSettings {
        let candidates: [(SettingsValidationError.Field, TimeInterval)] = [
            (.shortInterval, shortInterval),
            (.shortDuration, shortDuration),
            (.longInterval, longInterval),
            (.longDuration, longDuration),
            (.blinkInterval, blinkInterval),
            (.movementInterval, movementInterval),
            (.movementDuration, movementDuration),
        ]
        let issues = candidates.compactMap { field, value -> SettingsValidationError.Issue? in
            guard value.isFinite else { return .init(field: field, reason: .notFinite) }
            guard value > 0 else { return .init(field: field, reason: .notPositive) }
            return nil
        }
        guard issues.isEmpty else { throw SettingsValidationError(issues: issues) }
        return self
    }

    /// Replaces any timing that cannot be true with its recommended default, leaving every
    /// other field alone.
    ///
    /// This is for state that decoded successfully but is not meaningful — a hand-edited
    /// file, or one written by a build with a different idea of the schema. `validated()`
    /// rejects; this repairs, because refusing to start is a worse outcome than quietly
    /// restoring one interval.
    public func repaired() -> AppSettings {
        let recommended = AppSettings()
        func usable(_ value: TimeInterval, _ fallback: TimeInterval) -> TimeInterval {
            value.isFinite && value > 0 ? value : fallback
        }
        var result = self
        result.shortInterval = usable(shortInterval, recommended.shortInterval)
        result.shortDuration = usable(shortDuration, recommended.shortDuration)
        result.longInterval = usable(longInterval, recommended.longInterval)
        result.longDuration = usable(longDuration, recommended.longDuration)
        result.blinkInterval = usable(blinkInterval, recommended.blinkInterval)
        result.movementInterval = usable(movementInterval, recommended.movementInterval)
        result.movementDuration = usable(movementDuration, recommended.movementDuration)
        return result
    }

    /// Whether the timing or enablement of `kind` differs, i.e. whether that schedule restarts.
    public func scheduleChanged(_ kind: BreakKind, from other: AppSettings) -> Bool {
        switch kind {
        case .short:
            shortEnabled != other.shortEnabled
                || shortInterval != other.shortInterval
                || shortDuration != other.shortDuration
        case .long:
            longEnabled != other.longEnabled
                || longInterval != other.longInterval
                || longDuration != other.longDuration
        case .movement:
            // The activity is presentation only; choosing another one keeps the schedule.
            movementEnabled != other.movementEnabled
                || movementInterval != other.movementInterval
                || movementDuration != other.movementDuration
        }
    }

    /// Whether the blink cue's timing or enablement differs, i.e. whether its schedule restarts.
    public func blinkScheduleChanged(from other: AppSettings) -> Bool {
        blinkEnabled != other.blinkEnabled || blinkInterval != other.blinkInterval
    }

    public func interval(for kind: BreakKind) -> TimeInterval {
        switch kind {
        case .short: shortInterval
        case .long: longInterval
        case .movement: movementInterval
        }
    }

    public func duration(for kind: BreakKind) -> TimeInterval {
        switch kind {
        case .short: shortDuration
        case .long: longDuration
        case .movement: movementDuration
        }
    }

    public func isEnabled(_ kind: BreakKind) -> Bool {
        switch kind {
        case .short: shortEnabled
        case .long: longEnabled
        case .movement: movementEnabled
        }
    }
}
