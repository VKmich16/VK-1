import Foundation

/// Scheduling uses elapsed time, independent of the capped animation delta.
/// At most one request is in flight; reloading credentials invalidates its result.
struct PollSchedule {
    private(set) var interval: TimeInterval
    private(set) var nextPollAt: TimeInterval = 0
    private(set) var retryNotBefore: TimeInterval = 0
    private(set) var generation: UInt64 = 0
    private(set) var inFlight: UInt64?
    private var backoff: TimeInterval

    init(interval: TimeInterval) {
        self.interval = min(300, max(10, interval.isFinite ? interval : 30))
        backoff = self.interval
    }

    func canRefresh(at now: TimeInterval) -> Bool {
        inFlight == nil && now >= retryNotBefore
    }

    mutating func begin(at now: TimeInterval, force: Bool = false) -> UInt64? {
        guard canRefresh(at: now), force || now >= nextPollAt else { return nil }
        inFlight = generation
        return generation
    }

    /// Returns false for a result belonging to credentials that have been replaced.
    mutating func finish(_ request: UInt64, error: FetchError?, at now: TimeInterval) -> Bool {
        guard inFlight == request else { return false }
        inFlight = nil
        guard request == generation else {
            nextPollAt = max(now, retryNotBefore)
            return false
        }
        if case .rateLimited(let retry) = error {
            if let retry = retry, retry.isFinite, retry >= 0 {
                backoff = max(10, retry)
            } else {
                backoff = min(300, max(interval, backoff * 2))
            }
            retryNotBefore = now + backoff
            nextPollAt = retryNotBefore
        } else {
            backoff = interval
            retryNotBefore = 0
            nextPollAt = now + interval
        }
        return true
    }

    mutating func setInterval(_ seconds: TimeInterval, at now: TimeInterval) {
        interval = min(300, max(10, seconds.isFinite ? seconds : 30))
        nextPollAt = max(now + interval, retryNotBefore)
    }

    mutating func reload(at now: TimeInterval) {
        generation &+= 1
        backoff = interval
        retryNotBefore = 0
        nextPollAt = now
    }

    mutating func wake(at now: TimeInterval) {
        nextPollAt = max(now, retryNotBefore)
    }
}

enum PollScheduleSelfTests {
    static func run(_ expect: (Bool, String) -> Void) {
        var schedule = PollSchedule(interval: 30)
        let first = schedule.begin(at: 100)!
        expect(schedule.begin(at: 101, force: true) == nil, "manual refresh cannot overlap an active request")
        expect(schedule.finish(first, error: nil, at: 119), "current request is accepted")
        expect(schedule.begin(at: 130) == nil, "poll interval starts after request completion")
        let second = schedule.begin(at: 149)!
        expect(schedule.finish(second, error: .rateLimited(600), at: 150), "429 completes the request")
        expect(schedule.begin(at: 151, force: true) == nil, "manual refresh respects Retry-After")
        schedule.setInterval(10, at: 151)
        expect(schedule.begin(at: 749) == nil, "interval change cannot bypass Retry-After")
        let third = schedule.begin(at: 750)!
        schedule.reload(at: 751)
        expect(schedule.begin(at: 751, force: true) == nil, "credential reload waits for active request to finish")
        expect(!schedule.finish(third, error: .auth("old account"), at: 752), "stale credential response is discarded")
        let fourth = schedule.begin(at: 752)!
        expect(fourth != third, "new credentials use a new request generation")
        _ = schedule.finish(fourth, error: .rateLimited(nil), at: 753)
        expect(schedule.nextPollAt == 773, "missing Retry-After doubles the interval")
        schedule.wake(at: 760)
        expect(schedule.begin(at: 760) == nil, "waking cannot bypass server backoff")
        schedule.wake(at: 900)
        expect(schedule.begin(at: 900) != nil, "wake resumes an overdue poll")
    }
}
