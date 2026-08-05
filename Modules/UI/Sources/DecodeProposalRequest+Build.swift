import CosignCore

// The FFI and Indexer both define a `RelayInspectionEffect`; this scoped import
// binds the bare name to the FFI type (not a real duplicate of `import CosignCore`).
// swiftlint:disable:next duplicate_imports
import struct CosignCore.RelayInspectionEffect
import Indexer
import Squads

extension ConfigActionInfo {
    init(_ swift: SquadConfigAction) {
        self.init(
            memberKey: swift.memberKey,
            canInitiate: swift.canInitiate,
            canVote: swift.canVote,
            canExecute: swift.canExecute,
            newThreshold: swift.newThreshold,
            newTimeLock: swift.newTimeLockSeconds,
            newRentCollector: swift.newRentCollector,
            clearsRentCollector: swift.clearsRentCollector
        )
    }
}

extension DecodedInstruction {
    init(_ swift: SquadDecodedInstruction) {
        self.init(
            program: swift.program,
            kind: swift.kind,
            summary: swift.summary,
            accounts: swift.accounts,
            rawDataHex: swift.rawDataHex,
            configAction: swift.configAction.map(ConfigActionInfo.init)
        )
    }
}

extension RelayInspectionEffect {
    init(_ indexer: Indexer.RelayInspectionEffect) {
        self.init(
            kind: indexer.kind,
            summary: indexer.summary,
            program: indexer.program,
            asset: indexer.asset,
            amount: indexer.amount,
            source: indexer.source,
            destination: indexer.destination
        )
    }
}

// swiftlint:disable function_parameter_count
/// Builds the request the Rust core decodes. The app already holds the proposal
/// and the inspection effects; the core fetches the IDL/spec/mint augmentation.
func makeDecodeProposalRequest(
    relayBaseURL: String,
    capabilities: [String],
    proposal: SquadProposalDetail,
    ownVaultAccounts: Set<String>,
    effects: [Indexer.RelayInspectionEffect],
    lastAcceptedManifestIssuedAt: String?
) -> DecodeProposalRequest {
    DecodeProposalRequest(
        relayBaseUrl: relayBaseURL,
        relayCapabilities: capabilities,
        instructions: proposal.instructions.map(DecodedInstruction.init),
        accountsReferenced: proposal.accountsReferenced,
        ownVaultAccounts: Array(ownVaultAccounts),
        inspectionEffects: effects.map(RelayInspectionEffect.init),
        lastAcceptedManifestIssuedAt: lastAcceptedManifestIssuedAt
    )
}

// swiftlint:enable function_parameter_count
