import CosignCore
import Foundation
import Indexer
import Squads

/// Persists the last-accepted decode-keys manifest `issuedAt`, scoped per relay
/// base URL so switching relays (e.g. devnet ⇄ a self-hosted mainnet relay)
/// can't carry one relay's rollback floor onto another. A nil stored value means
/// "no manifest accepted yet" — the first valid, non-expired manifest is taken.
enum DecodeManifestFreshnessStore {
    private static let defaults = UserDefaults(suiteName: "com.hackshare.cosign.decode-registry") ?? .standard

    static func lastAcceptedIssuedAt(forRelayBaseURL relayBaseURL: String) -> String? {
        defaults.string(forKey: storageKey(forRelayBaseURL: relayBaseURL))
    }

    static func setLastAcceptedIssuedAt(_ issuedAt: String, forRelayBaseURL relayBaseURL: String) {
        defaults.set(issuedAt, forKey: storageKey(forRelayBaseURL: relayBaseURL))
    }

    private static func storageKey(forRelayBaseURL relayBaseURL: String) -> String {
        // Scope by the full base URL (scheme, host, port, path), not just the
        // host: two relays sharing a host but differing by port or path prefix
        // must keep independent floors, or one relay's newer issuedAt would make
        // the other's authentic older manifest look rolled back.
        "cosign.decodeRegistry.manifestIssuedAt.\(relayBaseURL)"
    }
}

extension ProposalDetailView {
    /// Decodes the proposal through the Rust core once the inspection effects are
    /// present. Driven from the inspection-load completion (not a racing task) so
    /// the effects that feed the cross-check are already loaded.
    @MainActor
    func runDecode() async {
        guard let proposal else {
            decodedProposal = nil
            return
        }
        let effects = currentInspectionEffects(for: proposal)
        // In a demo/offline profile the relay is a fixture host that serves no
        // real augmentation endpoints; passing an empty base URL takes the core's
        // no-fetch path, so the decode stays fully offline and still yields the
        // same tier-1/raw result the fixture relay would fail open to.
        let relayBaseURL = demoMode == nil ? indexerEnvironment.effectiveRPCURL.absoluteString : ""
        let request = makeDecodeProposalRequest(
            relayBaseURL: relayBaseURL,
            capabilities: RelayCapability.enhancedFeatures.map(\.rawValue),
            proposal: proposal,
            ownVaultAccounts: ownVaultAccounts,
            effects: effects,
            lastAcceptedManifestIssuedAt: DecodeManifestFreshnessStore
                .lastAcceptedIssuedAt(forRelayBaseURL: relayBaseURL)
        )
        let result = await CosignCore.decodeProposal(request)
        if let acceptedIssuedAt = result.acceptedManifestIssuedAt {
            DecodeManifestFreshnessStore.setLastAcceptedIssuedAt(acceptedIssuedAt, forRelayBaseURL: relayBaseURL)
        }
        decodedProposal = result
    }

    /// The inspection report's effects for the proposal's current state (executed
    /// vs. pre-sign), shared by the decode request and the movement/summary views
    /// that read the same report.
    func currentInspectionEffects(for proposal: SquadProposalDetail) -> [Indexer.RelayInspectionEffect] {
        (proposal.isExecuted ? executedInspectionReport?.action : inspectionReport?.action)?.effects ?? []
    }

    var decodedInstructions: [DecodedInstructionDisplay] {
        decodedProposal?.instructions ?? []
    }
}
