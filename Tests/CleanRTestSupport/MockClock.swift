import Foundation

/// A controllable clock for tests of date-based logic.
public final class MockClock: @unchecked Sendable {
    private var _now: Date

    public init(initial: Date = Date()) {
        self._now = initial
    }

    public func now() -> Date { _now }

    public func advance(by interval: TimeInterval) {
        _now = _now.addingTimeInterval(interval)
    }

    public func set(_ date: Date) {
        _now = date
    }
}
