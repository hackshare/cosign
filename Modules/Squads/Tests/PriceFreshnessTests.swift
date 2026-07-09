import Foundation
import Testing
@testable import Squads

struct PriceFreshnessTests {
    // MARK: - PriceFreshness.state boundaries

    @Test func freshAtZeroSeconds() {
        let base = Date()
        #expect(PriceFreshness.state(fetchedAt: base, now: base) == .fresh)
    }

    @Test func freshAt119Seconds() {
        let base = Date()
        let now = base.addingTimeInterval(119)
        #expect(PriceFreshness.state(fetchedAt: base, now: now) == .fresh)
    }

    @Test func staleAt120Seconds() {
        let base = Date()
        let now = base.addingTimeInterval(120)
        #expect(PriceFreshness.state(fetchedAt: base, now: now) == .stale(minutesOld: 2))
    }

    @Test func staleAt890Seconds() {
        let base = Date()
        let now = base.addingTimeInterval(890)
        // floor(890/60) = 14
        #expect(PriceFreshness.state(fetchedAt: base, now: now) == .stale(minutesOld: 14))
    }

    @Test func staleAt900Seconds() {
        let base = Date()
        let now = base.addingTimeInterval(900)
        // boundary: 900s = exactly 15m, still stale
        #expect(PriceFreshness.state(fetchedAt: base, now: now) == .stale(minutesOld: 15))
    }

    @Test func expiredAt901Seconds() {
        let base = Date()
        let now = base.addingTimeInterval(901)
        #expect(PriceFreshness.state(fetchedAt: base, now: now) == .expired)
    }

    // MARK: - PriceSnapshot accessors

    @Test func snapshotUsdReturnsValueForKnownMint() {
        let snapshot = PriceSnapshot(
            prices: ["SOL": 150.0],
            changes: ["SOL": 2.4],
            fetchedAt: Date()
        )
        #expect(snapshot.usd(for: "SOL") == 150.0)
    }

    @Test func snapshotUsdReturnsNilForUnknownMint() {
        let snapshot = PriceSnapshot(prices: [:], changes: [:], fetchedAt: Date())
        #expect(snapshot.usd(for: "UNKNOWN") == nil)
    }

    @Test func snapshotChange24hReturnsValueForKnownMint() {
        let snapshot = PriceSnapshot(
            prices: ["SOL": 150.0],
            changes: ["SOL": -1.55],
            fetchedAt: Date()
        )
        #expect(snapshot.change24h(for: "SOL") == -1.55)
    }

    @Test func snapshotChange24hReturnsNilForUnknownMint() {
        let snapshot = PriceSnapshot(prices: [:], changes: [:], fetchedAt: Date())
        #expect(snapshot.change24h(for: "UNKNOWN") == nil)
    }
}
