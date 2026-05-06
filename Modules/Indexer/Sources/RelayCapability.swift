import Foundation

/// A relay capability advertised at `/cosign/v1/capabilities`. The app assumes
/// its relay supports the enhanced add-ons (it ships against one), so this is
/// used to describe the HTTPRelayClient's feature set rather than to gate calls.
public struct RelayCapability: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let squadsIndexing = Self(rawValue: "squads_indexing")
    public static let squadDetail = Self(rawValue: "squad_detail")
    public static let squadProposals = Self(rawValue: "squad_proposals")
    public static let proposalDetail = Self(rawValue: "proposal_detail")
    public static let accountActivity = Self(rawValue: "account_activity")
    public static let transactionStatus = Self(rawValue: "transaction_status")
    public static let proposalInspection = Self(rawValue: "proposal_inspection")
    public static let executedTransactionInspection = Self(rawValue: "executed_transaction_inspection")
    public static let knownProgramDecoding = Self(rawValue: "known_program_decoding")
    public static let actionEffects = Self(rawValue: "action_effects")
    public static let assetPricing = Self(rawValue: "asset_pricing")

    public static let enhancedFeatures: Set<Self> = [
        .squadsIndexing,
        .squadDetail,
        .squadProposals,
        .proposalDetail,
        .accountActivity,
        .transactionStatus,
        .proposalInspection,
        .executedTransactionInspection,
        .knownProgramDecoding,
        .actionEffects,
        .assetPricing
    ]
}
