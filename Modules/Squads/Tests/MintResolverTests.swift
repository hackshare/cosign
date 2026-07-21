import Foundation
import Indexer
import Testing
@testable import Squads

private struct FakeMintRelay: RelayClient {
    let table: [String: MintMetadataResponse]

    func mintMetadataURL(for _: MintMetadataRequest) -> URL? {
        URL(string: "https://relay.test/m")
    }

    func mintMetadata(for request: MintMetadataRequest) async throws -> MintMetadataResponse {
        guard let hit = table[request.account] else { throw RelayClientError.unavailable }
        return hit
    }

    /// Unused surface throws / returns empty.
    func memberSquads(for _: MemberSquadsRequest) async throws -> MemberSquadsResponse {
        throw RelayClientError
            .unavailable
    }

    func squadDetail(for _: SquadDetailRequest) async throws -> SquadDetailResponse {
        throw RelayClientError
            .unavailable
    }

    func squadProposals(for _: SquadProposalsRequest) async throws -> SquadProposalsResponse {
        throw RelayClientError
            .unavailable
    }

    func squadProposal(for _: SquadProposalRequest) async throws -> SquadProposalResponse {
        throw RelayClientError
            .unavailable
    }

    func accountActivity(for _: AccountActivityRequest) async throws -> AccountActivityResponse {
        throw RelayClientError
            .unavailable
    }

    func transactionStatus(
        for _: TransactionStatusRequest
    ) async throws -> TransactionStatusResponse {
        throw RelayClientError.unavailable
    }

    func proposalInspectionURL(for _: ProposalInspectionRequest) -> URL? {
        nil
    }

    func proposalInspectionReport(
        for _: ProposalInspectionRequest
    ) async throws -> ProposalInspectionReport {
        throw RelayClientError.unavailable
    }

    func executedTransactionInspectionURL(for _: ExecutedTransactionInspectionRequest) -> URL? {
        nil
    }

    func executedTransactionInspectionReport(
        for _: ExecutedTransactionInspectionRequest
    ) async throws -> ExecutedTransactionInspectionReport {
        throw RelayClientError.unavailable
    }

    func prices(for _: [String]) async throws -> RelayPrices {
        RelayPrices(prices: [:])
    }

    func programIDLURL(for _: ProgramIDLRequest) -> URL? {
        nil
    }

    func programIDL(for _: ProgramIDLRequest) async throws -> ProgramIDLResponse {
        throw RelayClientError.unavailable
    }

    func decodeRegistryURL() -> URL? {
        nil
    }

    func decodeRegistry() async throws -> DecodeRegistryResponse {
        throw RelayClientError.unavailable
    }
}

struct MintResolverTests {
    @Test func resolvesKnownAccountsAndDropsFailures() async {
        let table = [
            "TA": MintMetadataResponse(account: "TA", mint: "MINT", decimals: 6, symbol: "USDC")
        ]
        let resolver = MintResolver(relay: FakeMintRelay(table: table))
        let mints = await resolver.resolve(accounts: ["TA", "UNKNOWN", "TA"])
        #expect(mints["TA"] == ResolvedMint(mint: "MINT", decimals: 6, symbol: "USDC"))
        #expect(mints["UNKNOWN"] == nil)
        #expect(mints.count == 1)
    }

    @Test func emptyInputYieldsEmpty() async {
        let resolver = MintResolver(relay: FakeMintRelay(table: [:]))
        #expect(await resolver.resolve(accounts: []).isEmpty)
    }
}
