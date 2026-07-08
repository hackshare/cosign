import Testing
@testable import Squads

struct SquadDetailRentCollectorTests {
    let knownAddress = "So11111111111111111111111111111111111111112"

    @Test func rentCollectorIsExposedWhenSet() {
        let detail = SquadDetail(
            address: "squad111",
            threshold: 1,
            timeLockSeconds: 0,
            rentCollector: knownAddress,
            transactionIndex: 1,
            staleTransactionIndex: 0,
            members: [],
            vaults: []
        )
        #expect(detail.rentCollector == knownAddress)
    }

    @Test func rentCollectorIsNilWhenNotSet() {
        let detail = SquadDetail(
            address: "squad111",
            threshold: 1,
            timeLockSeconds: 0,
            transactionIndex: 1,
            staleTransactionIndex: 0,
            members: [],
            vaults: []
        )
        #expect(detail.rentCollector == nil)
    }
}
