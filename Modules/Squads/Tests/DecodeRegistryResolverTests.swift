import CryptoKit
import Foundation
import Indexer
import Testing
@testable import Squads

private struct FakeRegistryRelay: RelayClient {
    let response: DecodeRegistryResponse?

    func decodeRegistryURL() -> URL? {
        URL(string: "https://relay.test/registry")
    }

    func decodeRegistry() async throws -> DecodeRegistryResponse {
        guard let response else { throw RelayClientError.unavailable }
        return response
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

    func mintMetadataURL(for _: MintMetadataRequest) -> URL? {
        nil
    }

    func mintMetadata(for _: MintMetadataRequest) async throws -> MintMetadataResponse {
        throw RelayClientError.unavailable
    }
}

private func signedBundle(specsJSON: String) throws -> (DecodeRegistryResponse, [String: String]) {
    let key = Curve25519.Signing.PrivateKey()
    let bundleJSON = "{\"schema\":1,\"keyId\":\"k1\",\"specs\":\(specsJSON)}"
    let data = Data(bundleJSON.utf8)
    let sig = try key.signature(for: data).base64EncodedString()
    return (
        DecodeRegistryResponse(bundleData: data, signatureBase64: sig),
        ["k1": key.publicKey.rawRepresentation.base64EncodedString()]
    )
}

struct DecodeRegistryResolverTests {
    @Test func resolvesAndIndexesSpecsByProgram() async throws {
        let spec = """
        [{ "program": "P1", "discriminator": [1], "mode": "standalone", "layout": [],
           "action": "Do", "accounts": {}, "template": "do", "effects": [] }]
        """
        let (response, keys) = try signedBundle(specsJSON: spec)
        let resolver = DecodeRegistryResolver(relay: FakeRegistryRelay(response: response), publicKeys: keys)
        let index = await resolver.resolve()
        #expect(index["P1"]?.count == 1)
        #expect(index["P1"]?[0].action == "Do")
    }

    @Test func returnsEmptyWhenUnavailable() async {
        let resolver = DecodeRegistryResolver(relay: FakeRegistryRelay(response: nil), publicKeys: [:])
        let index = await resolver.resolve()
        #expect(index.isEmpty)
    }

    @Test func returnsEmptyWhenSignatureInvalid() async throws {
        let (response, _) = try signedBundle(specsJSON: "[]")
        let resolver = DecodeRegistryResolver(relay: FakeRegistryRelay(response: response), publicKeys: [:])
        let index = await resolver.resolve()
        #expect(index.isEmpty)
    }
}
