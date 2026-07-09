import Foundation

public struct DemoRelayClient: RelayClient {
    public let fixture: CosignDemoFixture
    public let baseURL: URL

    public init(
        fixture: CosignDemoFixture,
        baseURL: URL = URL(string: "https://demo.cosign.local")!
    ) {
        self.fixture = fixture
        self.baseURL = baseURL
    }

    public func memberSquads(for request: MemberSquadsRequest) async throws -> MemberSquadsResponse {
        try fixture.memberSquads(for: request)
    }

    public func squadDetail(for request: SquadDetailRequest) async throws -> SquadDetailResponse {
        try fixture.squadDetail(for: request)
    }

    public func squadProposals(for request: SquadProposalsRequest) async throws -> SquadProposalsResponse {
        try fixture.squadProposals(for: request)
    }

    public func squadProposal(for request: SquadProposalRequest) async throws -> SquadProposalResponse {
        try fixture.squadProposal(for: request)
    }

    public func accountActivity(for request: AccountActivityRequest) async throws -> AccountActivityResponse {
        try fixture.accountActivity(for: request)
    }

    public func transactionStatus(for request: TransactionStatusRequest) async throws -> TransactionStatusResponse {
        try fixture.transactionStatus(for: request)
    }

    public func proposalInspectionURL(for request: ProposalInspectionRequest) -> URL? {
        demoURL(["squads", request.squadAddress, "transactions", String(request.transactionIndex), "inspection"])
    }

    public func proposalInspectionReport(
        for request: ProposalInspectionRequest
    ) async throws -> ProposalInspectionReport {
        try fixture.proposalInspectionReport(for: request)
    }

    public func executedTransactionInspectionURL(for request: ExecutedTransactionInspectionRequest) -> URL? {
        demoURL(["transactions", request.signature, "inspection"])
    }

    public func executedTransactionInspectionReport(
        for request: ExecutedTransactionInspectionRequest
    ) async throws -> ExecutedTransactionInspectionReport {
        try fixture.executedTransactionInspectionReport(for: request)
    }

    public func prices(for mints: [String]) async throws -> RelayPrices {
        RelayPrices(
            prices: CosignDemoPrices.usd.filter { mints.contains($0.key) },
            changes: CosignDemoPrices.changes24h.filter { mints.contains($0.key) }
        )
    }

    private func demoURL(_ pathComponents: [String]) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = (["cosign", "demo"] + pathComponents).joined(separator: "/").withLeadingSlash()
        return components.url
    }
}

/// Illustrative USD prices and 24h changes for the demo's mints.
/// Real builds fetch live prices via the relay.
enum CosignDemoPrices {
    static let usd: [String: Double] = [
        "So11111111111111111111111111111111111111112": 159.392295227591,
        "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v": 1.0,
        "jtojtomepa8beP8AuQc6eXt5FriJwfFMwQx2v2f9mCL": 3.0,
        "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263": 0.00002584
    ]

    /// Illustrative 24h percentage changes matching the design figure:
    /// SOL ▲ 2.4%, USDC flat 0.0%, JTO ▼ 1.1%, BONK ▲ 6.8%.
    static let changes24h: [String: Double] = [
        "So11111111111111111111111111111111111111112": 2.4,
        "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v": 0.0,
        "jtojtomepa8beP8AuQc6eXt5FriJwfFMwQx2v2f9mCL": -1.1,
        "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263": 6.8
    ]
}
