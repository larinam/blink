import Foundation

/// The scheduling engine.
///
/// Pure by construction: it imports Foundation only, never reads a clock, never starts a
/// timer and never touches disk. Every instant and duration is supplied by the adapter,
/// which makes the whole of the requirements' scheduling behaviour reproducible in tests.
///
/// Two clocks are in play and they are not interchangeable:
///
/// - `elapsed` is monotonic and includes system sleep. Durations — break countdowns, the
///   resume grace, absence lengths — use it, so an NTP step or a daylight-saving change
///   cannot disturb them.
/// - `now` is wall clock. Only the local day and the quiet-mode expiry use it, because
///   both are things the user reads off a calendar or the menu bar.
///
/// Counted screen time is a third notion, layered on `elapsed`: the app running, the Mac
/// unlocked and awake, and the user neither on a break nor idle.
public struct ReminderEngine: Sendable {
    public private(set) var state: EngineState
    private let calendar: Calendar

    /// Restores saved progress. Time while the app was closed is neither counted screen
    /// time nor credited rest: nothing accrues for the gap, and a break that was running
    /// at quit resumes with exactly the remaining duration it had, its countdown starting
    /// again only now that the process is running.
    public init(state: EngineState = EngineState(), now: Date = Date(), calendar: Calendar = .current) {
        self.state = state
        self.calendar = calendar
        // Decoded state is not trusted to be meaningful, only to be well-formed.
        self.state.normalize(now: now, calendar: calendar)
        self.state.absence = nil
        self.state.countedSinceLastInput = 0
        // Launch is a resume: give an already-overdue prompt the same settling time as one
        // surfacing after quiet mode, rather than flashing it during startup.
        self.state.graceRemaining = SchedulingConstants.resumeGrace
        rollOverDayIfNeeded(now: now)
        expireQuietIfNeeded(now: now)
    }

    // MARK: - Reading

    public var snapshot: EngineSnapshot {
        EngineSnapshot(
            settings: state.settings,
            summary: state.summary,
            status: status,
            shortRemaining: state.short.remaining,
            longRemaining: state.long.remaining,
            movementRemaining: state.movement.remaining,
            pendingBreak: canPresent ? state.dueBreak : nil,
            activeBreak: state.activeBreak,
            isQuiet: state.quietActive,
            quietUntil: state.quietUntil
        )
    }

    private var status: EngineStatus {
        if !state.settings.onboardingComplete { return .onboarding }
        if state.activeBreak != nil { return .onBreak }
        if state.quietActive { return .quiet }
        if state.absence != nil { return .idle }
        return .running
    }

    /// Whether a reminder may be shown at all. Quiet mode and absences hide reminders
    /// without stopping the schedules underneath them.
    private var canPresent: Bool {
        state.settings.onboardingComplete
            && !state.quietActive
            && state.graceRemaining <= 0
            && state.activeBreak == nil
            && state.absence == nil
    }

    // MARK: - Ticking

    /// Advances the engine. Safe to call at any rate: because `elapsed` is monotonic, a
    /// coalesced or delayed timer changes the resolution of the countdowns but not their
    /// correctness.
    ///
    /// - Parameters:
    ///   - now: wall clock, for the local day and quiet expiry.
    ///   - elapsed: monotonic seconds since the previous tick, including any sleep.
    ///   - unavailableElapsed: the portion of `elapsed` observed locked, asleep, with the
    ///     display off, or with the session switched away. Clamped to `0...elapsed`.
    ///   - idleSeconds: seconds since the last keyboard or pointer input.
    ///   - isUnavailable: availability at `now`, which tells the engine whether an
    ///     absence is still open.
    @discardableResult
    public mutating func tick(
        now: Date,
        elapsed: TimeInterval,
        unavailableElapsed: TimeInterval,
        idleSeconds: TimeInterval,
        isUnavailable: Bool
    ) -> [EngineEffect] {
        var elapsed = sanitized(elapsed)
        var unavailable = min(sanitized(unavailableElapsed), elapsed)
        let idleSeconds = sanitized(idleSeconds)

        // Decay first: a delayed tick that also expires the quiet period would otherwise
        // grant ten seconds of grace and subtract the whole interval from it in one go.
        state.graceRemaining = max(0, state.graceRemaining - elapsed)
        rollOverDayIfNeeded(now: now)
        expireQuietIfNeeded(now: now)

        guard state.settings.onboardingComplete else { return [] }

        var effects: [EngineEffect] = []

        // A running break consumes the front of the window. Its countdown uses raw
        // `elapsed`, so a break the user walked away from still finishes while the Mac
        // sleeps, and no counted screen time accrues meanwhile — which is what pauses the
        // long schedule during a short break.
        if let active = state.activeBreak {
            state.absence = nil
            guard active.remaining <= elapsed else {
                state.activeBreak = ActiveBreak(kind: active.kind, remaining: active.remaining - elapsed)
                return []
            }
            effects += completeBreak(
                active,
                now: now,
                elapsed: elapsed,
                unavailableElapsed: unavailable,
                isUnavailable: isUnavailable
            )
            // Whatever is left of the window is ordinary time and is evaluated below, so a
            // single coarse tick behaves exactly like the many fine ticks it stands in for.
            unavailable -= min(unavailable, active.remaining)
            elapsed -= active.remaining
        }

        let idleDetected = state.settings.idleDetectionEnabled && idleSeconds >= SchedulingConstants.idleThreshold
        let stillAbsent = isUnavailable || idleDetected
        // `unavailable > 0` matters on its own: the adapter reports a whole sleep span on
        // the wake tick, by which time the Mac is available again. Without this the
        // absence would go unnoticed and its scheduling credit lost.
        if stillAbsent || unavailable > 0 {
            continueAbsence(unavailable: unavailable, elapsed: elapsed, idleDetected: idleDetected, stillAbsent: stillAbsent)
        }
        guard !stillAbsent else { return effects }
        endAbsenceIfNeeded()

        accrue(max(0, elapsed - unavailable), idleSeconds: idleSeconds)
        evaluateDueBreak()
        if let cue = evaluateBlinkCue() { effects.append(cue) }
        return effects
    }

    // MARK: - Commands

    /// Starts a break, whether from the prompt or the menu's Start controls. The countdown
    /// begins here and nowhere else: a prompt never starts itself.
    public mutating func startBreak(_ kind: BreakKind, now: Date) {
        rollOverDayIfNeeded(now: now)
        guard state.settings.onboardingComplete, state.activeBreak == nil else { return }
        state.dueBreak = nil
        state.absence = nil
        state.activeBreak = ActiveBreak(kind: kind, remaining: state.settings.duration(for: kind))
    }

    /// Defers the pending occurrence by five minutes of counted screen time — not wall
    /// time, so a snoozed prompt does not resurface while the user is away from the desk.
    public mutating func snooze(now: Date) {
        rollOverDayIfNeeded(now: now)
        guard let due = state.dueBreak else { return }
        state.summary.snoozed += 1
        // Five counted minutes from *now*, not from when the prompt first appeared —
        // otherwise snoozing a prompt that sat unanswered leaves it instantly overdue.
        switch due {
        case .short: state.short.target = state.short.accrued + SchedulingConstants.snoozeCredit
        case .long: state.long.target = state.long.accrued + SchedulingConstants.snoozeCredit
        case .movement: state.movement.target = state.movement.accrued + SchedulingConstants.snoozeCredit
        }
        state.dueBreak = nil
    }

    /// Dismisses the pending occurrence and schedules its next normal interval. No rest is
    /// recorded, and an action on one kind never touches another kind's schedule.
    public mutating func skip(now: Date) {
        rollOverDayIfNeeded(now: now)
        guard let due = state.dueBreak else { return }
        state.summary.skipped += 1
        restartSchedule(for: due)
        state.dueBreak = nil
    }

    /// Ends a running break before its timer finishes. Counted as skipped: the timer did
    /// not complete, so no rest is credited.
    public mutating func endBreakEarly(now: Date) {
        rollOverDayIfNeeded(now: now)
        guard let active = state.activeBreak else { return }
        state.activeBreak = nil
        state.summary.skipped += 1
        restartSchedule(for: active.kind)
        clearPostBreakAccrual()
    }

    /// Enters quiet mode until `until`, or indefinitely when it is nil. Eligible screen
    /// time keeps accumulating; only presentation stops.
    public mutating func setQuiet(until: Date?, now: Date) {
        rollOverDayIfNeeded(now: now)
        // Never leave a break running invisibly behind a quiet period.
        if state.activeBreak != nil { endBreakEarly(now: now) }
        state.quietActive = true
        state.quietUntil = until
    }

    public mutating func resume(now: Date) {
        rollOverDayIfNeeded(now: now)
        guard state.quietActive else { return }
        state.quietActive = false
        state.quietUntil = nil
        state.graceRemaining = SchedulingConstants.resumeGrace
    }

    /// Applies validated settings, restarting only the schedules whose timing or
    /// enablement changed. Onboarding completion is carried forward regardless of the
    /// incoming value, so "Restore recommended defaults" cannot send the user back
    /// through onboarding.
    public mutating func updateSettings(_ settings: AppSettings, now: Date) throws {
        rollOverDayIfNeeded(now: now)
        var incoming = try settings.validated()
        incoming.onboardingComplete = state.settings.onboardingComplete

        let previous = state.settings
        state.settings = incoming
        if incoming.scheduleChanged(.short, from: previous) { restartSchedule(for: .short) }
        if incoming.scheduleChanged(.long, from: previous) { restartSchedule(for: .long) }
        if incoming.scheduleChanged(.movement, from: previous) { restartSchedule(for: .movement) }
        if incoming.blinkScheduleChanged(from: previous) { state.blink.restart(interval: incoming.blinkInterval) }
    }

    /// Finishes onboarding and starts every schedule fresh. Scheduling does nothing before
    /// this is called.
    public mutating func completeOnboarding(now: Date) {
        state.settings.onboardingComplete = true
        state.short.restart(interval: state.settings.shortInterval)
        state.long.restart(interval: state.settings.longInterval)
        state.movement.restart(interval: state.settings.movementInterval)
        state.blink.restart(interval: state.settings.blinkInterval)
        state.dueBreak = nil
        state.activeBreak = nil
        state.absence = nil
        state.countedSinceLastInput = 0
        state.graceRemaining = 0
        rollOverDayIfNeeded(now: now)
    }

    // MARK: - Breaks

    /// Retires a break whose timer ran out inside this tick's window.
    private mutating func completeBreak(
        _ active: ActiveBreak,
        now: Date,
        elapsed: TimeInterval,
        unavailableElapsed: TimeInterval,
        isUnavailable: Bool
    ) -> [EngineEffect] {
        // The timer ran out `active.remaining` seconds into this window, which for a wake
        // tick is an hour ago rather than now. Both the chime and the day the completion
        // belongs to depend on that instant, not on the instant the tick arrived.
        let completedAt = now.addingTimeInterval(active.remaining - elapsed)
        // Unavailable time sits at the front of the window, so the timer was audible only
        // if it outlasted that. The `isUnavailable` term adds nothing for a window that is
        // wholly unavailable, and is kept only because erring towards silence is far better
        // than chiming into a sleeping Mac.
        let completedWhileAvailable = !isUnavailable && active.remaining > unavailableElapsed

        state.activeBreak = nil
        // Today's counters only. A break that ran out before midnight belongs to a day
        // whose summary has already been discarded.
        if state.summary.covers(completedAt, calendar: calendar) {
            state.summary.recordCompletion(of: active.kind)
        }
        switch active.kind {
        case .short:
            restartSchedule(for: .short)
        case .long:
            // A completed long break resets every break schedule.
            restartSchedule(for: .short)
            restartSchedule(for: .long)
            restartSchedule(for: .movement)
        case .movement:
            // Time away from the screen rests the eyes too. The long schedule is only paused:
            // two minutes is not the longer rest.
            restartSchedule(for: .short)
            restartSchedule(for: .movement)
        }
        clearPostBreakAccrual()

        // No chime into a sleeping or locked Mac, and never replayed on wake.
        return completedWhileAvailable ? [.breakCompleted(active.kind)] : []
    }

    /// Break time is not counted screen time, so nothing accrued during it may later be
    /// rolled back by idle detection — which is what stops a finished long break from
    /// immediately rewinding the schedule it just reset.
    private mutating func clearPostBreakAccrual() {
        state.dueBreak = nil
        state.countedSinceLastInput = 0
        state.blink.restart(interval: state.settings.blinkInterval)
    }

    private mutating func restartSchedule(for kind: BreakKind) {
        switch kind {
        case .short: state.short.restart(interval: state.settings.shortInterval)
        case .long: state.long.restart(interval: state.settings.longInterval)
        case .movement: state.movement.restart(interval: state.settings.movementInterval)
        }
        if state.dueBreak == kind { state.dueBreak = nil }
    }

    // MARK: - Absences

    private mutating func continueAbsence(
        unavailable: TimeInterval,
        elapsed: TimeInterval,
        idleDetected: Bool,
        stillAbsent: Bool
    ) {
        var absence = state.absence ?? Absence()
        absence.unavailableSeconds += unavailable
        // A tick the absence outlives belongs to it whole; one it ends inside contributes
        // only its unavailable part, the rest being screen time about to be counted.
        absence.totalSeconds += stillAbsent ? elapsed : unavailable

        if idleDetected && !absence.idleDetected {
            absence.idleDetected = true
            // The absence began at the last input, so the time already counted since then
            // has to come back off — but only as much as was actually counted. After a
            // sleep span the engine credited nothing, and removes nothing.
            let rollback = min(SchedulingConstants.idleThreshold, state.countedSinceLastInput)
            state.short.rollBack(rollback)
            state.long.rollBack(rollback)
            state.movement.rollBack(rollback)
            state.blink.rollBack(rollback)
            absence.totalSeconds += rollback
            state.countedSinceLastInput = 0
        }

        if !absence.didResetShort
            && (absence.unavailableSeconds >= SchedulingConstants.unavailableShortReset || absence.idleDetected) {
            absence.didResetShort = true
            restartSchedule(for: .short)
        }
        // An idle detection already means five minutes without input.
        if !absence.didResetMovement
            && (absence.totalSeconds >= SchedulingConstants.movementReset || absence.idleDetected) {
            absence.didResetMovement = true
            restartSchedule(for: .movement)
        }
        if !absence.didResetBoth && absence.totalSeconds >= SchedulingConstants.bothReset {
            absence.didResetBoth = true
            restartSchedule(for: .short)
            restartSchedule(for: .long)
            restartSchedule(for: .movement)
        }

        state.absence = absence
    }

    private mutating func endAbsenceIfNeeded() {
        guard state.absence != nil else { return }
        state.absence = nil
        state.countedSinceLastInput = 0
        // The user has just come back from a rest; the next cue is a full interval away.
        state.blink.restart(interval: state.settings.blinkInterval)
        state.graceRemaining = SchedulingConstants.resumeGrace
    }

    // MARK: - Accrual and due evaluation

    private mutating func accrue(_ countable: TimeInterval, idleSeconds: TimeInterval) {
        if state.settings.shortEnabled { state.short.accrued += countable }
        if state.settings.longEnabled { state.long.accrued += countable }
        if state.settings.movementEnabled { state.movement.accrued += countable }
        if state.settings.blinkEnabled { state.blink.accrued += countable }
        // Can never exceed the time since the last input, which is what keeps the idle
        // rollback honest across sleep and lock.
        state.countedSinceLastInput = min(state.countedSinceLastInput + countable, idleSeconds)
    }

    /// Priority is long, movement, then short. A due break replaces any lower-priority
    /// occurrence that is due or already pending: the lower one is consumed and given a
    /// fresh interval, with no completion and no skip recorded — the user was never offered
    /// it, and the higher break gives at least the same rest.
    private mutating func evaluateDueBreak() {
        let longDue = state.settings.longEnabled && state.long.isDue
        let movementDue = state.settings.movementEnabled && state.movement.isDue
        let shortDue = state.settings.shortEnabled && state.short.isDue

        if longDue {
            if movementDue || state.dueBreak == .movement { restartSchedule(for: .movement) }
            if shortDue || state.dueBreak == .short { restartSchedule(for: .short) }
            state.dueBreak = .long
        } else if movementDue && state.dueBreak != .long {
            if shortDue || state.dueBreak == .short { restartSchedule(for: .short) }
            state.dueBreak = .movement
        } else if shortDue && state.dueBreak == nil {
            state.dueBreak = .short
        }
    }

    private mutating func evaluateBlinkCue() -> EngineEffect? {
        guard state.settings.blinkEnabled, state.blink.isDue else { return nil }
        // Reset before deciding whether to show it: a cue that lands during a prompt or a
        // quiet period is discarded, never queued for later.
        state.blink.restart(interval: state.settings.blinkInterval)
        guard canPresent, state.dueBreak == nil else { return nil }
        return .blink
    }

    // MARK: - Wall-clock bookkeeping

    private mutating func rollOverDayIfNeeded(now: Date) {
        guard !state.summary.covers(now, calendar: calendar) else { return }
        // Counters only. Schedule progress deliberately survives midnight.
        state.summary = DailySummary(now: now, calendar: calendar)
    }

    private mutating func expireQuietIfNeeded(now: Date) {
        guard state.quietActive, let until = state.quietUntil, now >= until else { return }
        state.quietActive = false
        state.quietUntil = nil
        state.graceRemaining = SchedulingConstants.resumeGrace
    }

    private func sanitized(_ value: TimeInterval) -> TimeInterval {
        value.isFinite ? max(0, value) : 0
    }
}
