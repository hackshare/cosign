import Foundation

public protocol RelayClient: Sendable {
    func memberSquads(for request: MemberSquadsRequest) async throws -> MemberSquadsResponse
    func squadDetail(for request: SquadDetailRequest) async throws -> SquadDetailResponse
    func squadProposals(for request: SquadProposalsRequest) async throws -> SquadProposalsResponse
    func squadProposal(for request: SquadProposalRequest) async throws -> SquadProposalResponse
    func accountActivity(for request: AccountActivityRequest) async throws -> AccountActivityResponse
    func transactionStatus(for request: TransactionStatusRequest) async throws -> TransactionStatusResponse
    func proposalInspectionURL(for request: ProposalInspectionRequest) -> URL?
    func proposalInspectionReport(
        for request: ProposalInspectionRequest
    ) async throws -> ProposalInspectionReport
    func executedTransactionInspectionURL(for request: ExecutedTransactionInspectionRequest) -> URL?
    func executedTransactionInspectionReport(
        for request: ExecutedTransactionInspectionRequest
    ) async throws -> ExecutedTransactionInspectionReport
    func prices(for mints: [String]) async throws -> RelayPrices
    func programIDLURL(for request: ProgramIDLRequest) -> URL?
    func programIDL(for request: ProgramIDLRequest) async throws -> ProgramIDLResponse
    func decodeRegistryURL() -> URL?
    func decodeRegistry() async throws -> DecodeRegistryResponse
    func mintMetadataURL(for request: MintMetadataRequest) -> URL?
    func mintMetadata(for request: MintMetadataRequest) async throws -> MintMetadataResponse
}

public struct NoOpRelay: RelayClient {
    public init() {}

    public func memberSquads(for _: MemberSquadsRequest) async throws -> MemberSquadsResponse {
        throw RelayClientError.unavailable
    }

    public func squadDetail(for _: SquadDetailRequest) async throws -> SquadDetailResponse {
        throw RelayClientError.unavailable
    }

    public func squadProposals(for _: SquadProposalsRequest) async throws -> SquadProposalsResponse {
        throw RelayClientError.unavailable
    }

    public func squadProposal(for _: SquadProposalRequest) async throws -> SquadProposalResponse {
        throw RelayClientError.unavailable
    }

    public func accountActivity(for _: AccountActivityRequest) async throws -> AccountActivityResponse {
        throw RelayClientError.unavailable
    }

    public func transactionStatus(for _: TransactionStatusRequest) async throws -> TransactionStatusResponse {
        throw RelayClientError.unavailable
    }

    public func proposalInspectionURL(for _: ProposalInspectionRequest) -> URL? {
        nil
    }

    public func proposalInspectionReport(for _: ProposalInspectionRequest) async throws -> ProposalInspectionReport {
        throw RelayClientError.unavailable
    }

    public func executedTransactionInspectionURL(for _: ExecutedTransactionInspectionRequest) -> URL? {
        nil
    }

    public func executedTransactionInspectionReport(
        for _: ExecutedTransactionInspectionRequest
    ) async throws -> ExecutedTransactionInspectionReport {
        throw RelayClientError.unavailable
    }

    public func prices(for _: [String]) async throws -> RelayPrices {
        throw RelayClientError.unavailable
    }

    public func programIDLURL(for _: ProgramIDLRequest) -> URL? {
        nil
    }

    public func programIDL(for _: ProgramIDLRequest) async throws -> ProgramIDLResponse {
        throw RelayClientError.unavailable
    }

    public func decodeRegistryURL() -> URL? {
        nil
    }

    public func decodeRegistry() async throws -> DecodeRegistryResponse {
        throw RelayClientError.unavailable
    }

    public func mintMetadataURL(for _: MintMetadataRequest) -> URL? {
        nil
    }

    public func mintMetadata(for _: MintMetadataRequest) async throws -> MintMetadataResponse {
        throw RelayClientError.unavailable
    }
}

// SAFETY: all stored state is immutable (`let`); the JSONDecoder is never reconfigured
// after init, so concurrent decoding is safe.
final class HTTPRelayClient: RelayClient, @unchecked Sendable {
    let baseURL: URL
    private let capabilities: Set<RelayCapability>?
    let session: URLSession
    let healthReporter: NetworkHealthReporter?
    let decoder = JSONDecoder()

    init(
        baseURL: URL,
        capabilities: Set<RelayCapability>? = nil,
        session: URLSession = .shared,
        healthReporter: NetworkHealthReporter? = nil
    ) {
        self.baseURL = baseURL
        self.capabilities = capabilities
        self.session = session
        self.healthReporter = healthReporter
    }

    func memberSquadsURL(for request: MemberSquadsRequest) -> URL? {
        guard supports(.squadsIndexing) else {
            return nil
        }

        return relayURL(pathComponents: [
            "cosign",
            "v1",
            "members",
            request.memberAddress,
            "squads"
        ])
    }

    func squadDetailURL(for request: SquadDetailRequest) -> URL? {
        guard supports(.squadDetail) else {
            return nil
        }

        return relayURL(pathComponents: [
            "cosign",
            "v1",
            "squads",
            request.squadAddress
        ])
    }

    func squadProposalsURL(for request: SquadProposalsRequest) -> URL? {
        guard supports(.squadProposals) else {
            return nil
        }

        return relayURL(
            pathComponents: [
                "cosign",
                "v1",
                "squads",
                request.squadAddress,
                "proposals"
            ],
            queryItems: [
                URLQueryItem(name: "from", value: String(request.fromIndex)),
                URLQueryItem(name: "to", value: String(request.toIndex))
            ]
        )
    }

    func squadProposalURL(for request: SquadProposalRequest) -> URL? {
        guard supports(.proposalDetail) else {
            return nil
        }

        return relayURL(pathComponents: [
            "cosign",
            "v1",
            "squads",
            request.squadAddress,
            "proposals",
            String(request.transactionIndex)
        ])
    }

    func accountActivityURL(for request: AccountActivityRequest) -> URL? {
        guard supports(.accountActivity) else {
            return nil
        }

        var queryItems = [URLQueryItem(name: "limit", value: String(request.limit))]
        if let beforeSignature = request.beforeSignature {
            queryItems.append(URLQueryItem(name: "before", value: beforeSignature))
        }

        return relayURL(
            pathComponents: [
                "cosign",
                "v1",
                "accounts",
                request.address,
                "activity"
            ],
            queryItems: queryItems
        )
    }

    func proposalInspectionURL(for request: ProposalInspectionRequest) -> URL? {
        guard supports(.proposalInspection) else {
            return nil
        }

        return relayURL(pathComponents: [
            "cosign",
            "v1",
            "squads",
            request.squadAddress,
            "transactions",
            String(request.transactionIndex),
            "inspection"
        ])
    }

    func transactionStatusURL(for request: TransactionStatusRequest) -> URL? {
        guard supports(.transactionStatus) else {
            return nil
        }

        return relayURL(pathComponents: [
            "cosign",
            "v1",
            "transactions",
            request.signature,
            "status"
        ])
    }

    func executedTransactionInspectionURL(for request: ExecutedTransactionInspectionRequest) -> URL? {
        guard supports(.executedTransactionInspection) else {
            return nil
        }

        return relayURL(pathComponents: [
            "cosign",
            "v1",
            "transactions",
            request.signature,
            "inspection"
        ])
    }

    func relayURL(
        pathComponents: [String],
        queryItems: [URLQueryItem] = []
    ) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let basePath = components.percentEncodedPath.trimmingTrailingSlash()
        components.percentEncodedPath = ([basePath] + pathComponents)
            .filter { !$0.isEmpty }
            .joined(separator: "/")
            .withLeadingSlash()

        if !queryItems.isEmpty {
            components.queryItems = (components.queryItems ?? []) + queryItems
        }

        return components.url
    }

    func supports(_ capability: RelayCapability) -> Bool {
        capabilities?.contains(capability) ?? true
    }

    func memberSquads(for request: MemberSquadsRequest) async throws -> MemberSquadsResponse {
        guard let url = memberSquadsURL(for: request) else {
            throw RelayClientError.unavailable
        }

        return try await loadJSON(MemberSquadsResponse.self, from: url)
    }

    func squadDetail(for request: SquadDetailRequest) async throws -> SquadDetailResponse {
        guard let url = squadDetailURL(for: request) else {
            throw RelayClientError.unavailable
        }

        return try await loadJSON(SquadDetailResponse.self, from: url)
    }

    func squadProposals(for request: SquadProposalsRequest) async throws -> SquadProposalsResponse {
        guard let url = squadProposalsURL(for: request) else {
            throw RelayClientError.unavailable
        }

        return try await loadJSON(SquadProposalsResponse.self, from: url)
    }

    func squadProposal(for request: SquadProposalRequest) async throws -> SquadProposalResponse {
        guard let url = squadProposalURL(for: request) else {
            throw RelayClientError.unavailable
        }

        return try await loadJSON(SquadProposalResponse.self, from: url)
    }

    func accountActivity(for request: AccountActivityRequest) async throws -> AccountActivityResponse {
        guard let url = accountActivityURL(for: request) else {
            throw RelayClientError.unavailable
        }

        return try await loadJSON(AccountActivityResponse.self, from: url)
    }

    func transactionStatus(for request: TransactionStatusRequest) async throws -> TransactionStatusResponse {
        guard let url = transactionStatusURL(for: request) else {
            throw RelayClientError.unavailable
        }

        return try await loadJSON(TransactionStatusResponse.self, from: url)
    }

    func proposalInspectionReport(
        for request: ProposalInspectionRequest
    ) async throws -> ProposalInspectionReport {
        guard let url = proposalInspectionJSONURL(for: request) else {
            throw RelayClientError.unavailable
        }

        return try await loadJSON(ProposalInspectionReport.self, from: url)
    }

    func executedTransactionInspectionReport(
        for request: ExecutedTransactionInspectionRequest
    ) async throws -> ExecutedTransactionInspectionReport {
        guard let url = executedTransactionInspectionJSONURL(for: request) else {
            throw RelayClientError.unavailable
        }

        return try await loadJSON(ExecutedTransactionInspectionReport.self, from: url)
    }

    func prices(for mints: [String]) async throws -> RelayPrices {
        guard
            !mints.isEmpty,
            let url = relayURL(
                pathComponents: ["cosign", "v1", "prices"],
                queryItems: [URLQueryItem(name: "ids", value: mints.joined(separator: ","))]
            )
        else {
            return RelayPrices(prices: [:])
        }
        return try await loadJSON(RelayPrices.self, from: url)
    }

    func proposalInspectionJSONURL(for request: ProposalInspectionRequest) -> URL? {
        guard
            let url = proposalInspectionURL(for: request),
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "format" }
        queryItems.append(URLQueryItem(name: "format", value: "json"))
        components.queryItems = queryItems
        return components.url
    }

    func executedTransactionInspectionJSONURL(for request: ExecutedTransactionInspectionRequest) -> URL? {
        guard
            let url = executedTransactionInspectionURL(for: request),
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "format" }
        queryItems.append(URLQueryItem(name: "format", value: "json"))
        components.queryItems = queryItems
        return components.url
    }
}
