import Foundation
import Testing
@testable import Indexer

struct ReadThroughCacheTests {
    @Test func returnsCachedValueUntilTTLExpires() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 0))
        let probe = LoaderProbe()
        let cache = ReadThroughCache<String, String>(defaultTTL: 10) { clock.current }

        let first = try await cache.value(for: "member") {
            await probe.load("first")
        }
        let second = try await cache.value(for: "member") {
            await probe.load("second")
        }

        #expect(first == "first")
        #expect(second == "first")
        #expect(await probe.calls == 1)

        clock.current = clock.current.addingTimeInterval(11)
        let third = try await cache.value(for: "member") {
            await probe.load("third")
        }

        #expect(third == "third")
        #expect(await probe.calls == 2)
    }

    @Test func removeAllForcesReload() async throws {
        let probe = LoaderProbe()
        let cache = ReadThroughCache<String, String>(defaultTTL: 60)

        _ = try await cache.value(for: "proposal") {
            await probe.load("first")
        }
        await cache.removeAll()
        let reloaded = try await cache.value(for: "proposal") {
            await probe.load("second")
        }

        #expect(reloaded == "second")
        #expect(await probe.calls == 2)
    }

    @Test func removeValueOnlyInvalidatesMatchingKey() async throws {
        let probe = LoaderProbe()
        let cache = ReadThroughCache<String, String>(defaultTTL: 60)

        _ = try await cache.value(for: "squad-a") {
            await probe.load("first-a")
        }
        _ = try await cache.value(for: "squad-b") {
            await probe.load("first-b")
        }

        await cache.removeValue(for: "squad-a")

        let reloaded = try await cache.value(for: "squad-a") {
            await probe.load("second-a")
        }
        let cached = try await cache.value(for: "squad-b") {
            await probe.load("second-b")
        }

        #expect(reloaded == "second-a")
        #expect(cached == "first-b")
        #expect(await probe.calls == 3)
    }
}

private final class TestClock: @unchecked Sendable {
    var current: Date

    init(_ current: Date) {
        self.current = current
    }
}

private actor LoaderProbe {
    private var callCount = 0

    var calls: Int {
        callCount
    }

    func load(_ value: String) -> String {
        callCount += 1
        return value
    }
}
