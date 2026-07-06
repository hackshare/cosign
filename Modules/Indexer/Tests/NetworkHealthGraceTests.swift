import Foundation
import Testing
@testable import Indexer

struct NetworkHealthGraceTests {
    private func currentStatus(_ health: NetworkHealth) async -> NetworkHealthStatus {
        await MainActor.run { health.status }
    }

    /// Poll (rather than sleep a fixed amount) so the positive direction is not
    /// sensitive to scheduling jitter.
    private func waitForStatus(
        _ health: NetworkHealth,
        _ expected: NetworkHealthStatus,
        timeout: Duration
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await currentStatus(health) == expected {
                return true
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await currentStatus(health) == expected
    }

    @Test func webSocketDownAppearsOnlyAfterTheGraceWindow() async {
        let health = NetworkHealth(webSocketGrace: .milliseconds(250))
        let reporter = health.reporter()

        reporter.failure(.webSocket)
        // Well within the grace window the banner must not have appeared yet.
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await currentStatus(health) == .healthy)

        // Past the window, with the socket still down, it surfaces.
        #expect(await waitForStatus(health, .webSocketDown, timeout: .milliseconds(1500)))
    }

    @Test func quickRecoveryWithinGraceNeverTripsTheBanner() async {
        let health = NetworkHealth(webSocketGrace: .milliseconds(250))
        let reporter = health.reporter()

        reporter.failure(.webSocket)
        try? await Task.sleep(for: .milliseconds(30))
        reporter.success(.webSocket)

        // Wait past the original grace window; the banner must stay clear.
        try? await Task.sleep(for: .milliseconds(400))
        #expect(await currentStatus(health) == .healthy)
    }

    @Test func relayFailuresGoOfflineWithoutGrace() async {
        let health = NetworkHealth(webSocketGrace: .seconds(4))
        let reporter = health.reporter()

        reporter.failure(.relay)
        reporter.failure(.relay)
        #expect(await waitForStatus(health, .offline, timeout: .milliseconds(500)))
    }
}
