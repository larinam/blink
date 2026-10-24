import Foundation

/// Partitions a continuous monotonic interval at observed OS availability
/// transitions. A wake sample attributes the suspended interval to sleep,
/// even though the current sample is already awake.
struct AvailabilityClock {
    struct Interval: Equatable {
        let elapsed: TimeInterval
        let unavailableElapsed: TimeInterval
    }
    private var previous: TimeInterval
    private var previousSuspending: TimeInterval?
    private var wasUnavailable: Bool

    init(time: TimeInterval, suspendingTime: TimeInterval? = nil, isUnavailable: Bool) {
        previous = time
        previousSuspending = suspendingTime
        wasUnavailable = isUnavailable
    }

    mutating func sample(time: TimeInterval, suspendingTime: TimeInterval? = nil, isUnavailable: Bool) -> Interval {
        let elapsed = max(0, time - previous)
        // SuspendingClock stops during system sleep; ContinuousClock does not.
        // Their difference recovers missed sleep notifications without treating
        // a busy/stalled run loop as a rest. Ignore sub-second clock sampling skew.
        let sleep: TimeInterval
        if let suspendingTime, let previousSuspending {
            let difference = elapsed - max(0, suspendingTime - previousSuspending)
            sleep = difference >= 1 ? min(difference, elapsed) : 0
        } else { sleep = 0 }
        let interval = Interval(elapsed: elapsed, unavailableElapsed: wasUnavailable ? elapsed : sleep)
        previous = time
        previousSuspending = suspendingTime
        wasUnavailable = isUnavailable
        return interval
    }
}

func seconds(_ duration: Duration) -> TimeInterval {
    let parts = duration.components
    return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
}
