import Foundation
import Indexer
import Testing
@testable import Squads

private struct FakeRelay: RelayClient {
    let idls: [String: AnchorIDLDocument]

    func programIDLURL(for _: ProgramIDLRequest) -> URL? {
        nil
    }

    func programIDL(for request: ProgramIDLRequest) async throws -> ProgramIDLResponse {
        guard let document = idls[request.programID] else {
            throw RelayClientError.unavailable
        }
        return ProgramIDLResponse(
            kind: "program_idl", cluster: nil, program: request.programID,
            idl: document, hash: "hash-\(request.programID)", slot: 5, authority: nil
        )
    }

    /// Unused surface throws.
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

    func decodeRegistryURL() -> URL? {
        nil
    }

    func decodeRegistry() async throws -> DecodeRegistryResponse {
        throw RelayClientError.unavailable
    }

    func mintMetadataURL(for _: MintMetadataRequest) -> URL? {
        nil
    }

    func mintMetadata(for _: MintMetadataRequest) async throws -> MintMetadataResponse {
        throw RelayClientError.unavailable
    }
}

private func document(named name: String) throws -> AnchorIDLDocument {
    let json = "{ \"metadata\": { \"name\": \"\(name)\" }, \"instructions\": [] }"
    return try JSONDecoder().decode(AnchorIDLDocument.self, from: Data(json.utf8))
}

struct ProgramIDLResolverTests {
    @Test func resolvesAvailableAndDropsMissing() async throws {
        let relay = try FakeRelay(idls: ["a": document(named: "alpha")])
        let resolver = ProgramIDLResolver(relay: relay)

        let resolved = await resolver.resolve(programIDs: ["a", "b", "a"])

        #expect(resolved.keys.sorted() == ["a"])
        #expect(resolved["a"]?.document.name == "alpha")
        #expect(resolved["a"]?.provenance == .onChainIDL(idlName: "alpha", hash: "hash-a", slot: 5))
    }

    @Test func returnsEmptyForNoPrograms() async {
        let resolver = ProgramIDLResolver(relay: FakeRelay(idls: [:]))
        let resolved = await resolver.resolve(programIDs: [])
        #expect(resolved.isEmpty)
    }
}
