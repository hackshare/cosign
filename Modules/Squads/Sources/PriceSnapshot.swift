import Foundation

/// A point-in-time snapshot of USD prices and 24h change percentages for a
/// set of mints, stamped with the instant the relay returned the data.
/// Freshness is derived via `PriceFreshness.state(fetchedAt:now:)` so it
/// can be computed deterministically against any clock in tests.
public struct PriceSnapshot: Sendable, Equatable {
    public let prices: [String: Double]
    public let changes: [String: Double]
    public let fetchedAt: Date

    public init(prices: [String: Double], changes: [String: Double], fetchedAt: Date) {
        self.prices = prices
        self.changes = changes
        self.fetchedAt = fetchedAt
    }

    /// USD value for `mint`, or nil if the mint was not priced in this snapshot.
    public func usd(for mint: String) -> Double? {
        prices[mint]
    }

    /// 24h percentage change for `mint` (e.g. -1.55), or nil if unavailable.
    public func change24h(for mint: String) -> Double? {
        changes[mint]
    }

    /// Freshness relative to a caller-supplied clock (defaults to now).
    public func freshness(now: Date = Date()) -> PriceFreshness {
        PriceFreshness.state(fetchedAt: fetchedAt, now: now)
    }
}

public extension PriceFreshness {
    /// True when the snapshot is past the 15-minute expiry threshold.
    var isExpired: Bool {
        if case .expired = self { return true }
        return false
    }
}

/// How old a price snapshot is, expressed as a three-level freshness ladder.
///
/// - fresh:  fetched within the last 2 minutes — display at full strength.
/// - stale:  2–15 minutes old — dim the USD value and surface the age.
/// - expired: more than 15 minutes old — hide the USD value entirely.
public enum PriceFreshness: Equatable, Sendable {
    case fresh
    case stale(minutesOld: Int)
    case expired

    /// Derives the freshness level from the elapsed time since `fetchedAt`.
    /// Thresholds: < 120 s → fresh; 120–900 s → stale; > 900 s → expired.
    /// `minutesOld` is `floor(elapsed / 60)`.
    public static func state(fetchedAt: Date, now: Date) -> PriceFreshness {
        let elapsed = now.timeIntervalSince(fetchedAt)
        if elapsed < 120 {
            return .fresh
        } else if elapsed <= 900 {
            return .stale(minutesOld: Int(elapsed / 60))
        } else {
            return .expired
        }
    }
}
