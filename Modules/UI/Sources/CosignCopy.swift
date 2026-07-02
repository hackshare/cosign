import Indexer
import Provenance

public enum CosignCopy {}

extension CosignCopy {
    public enum Common {
        static let appName = "cosign"
        public static let devnetSeedSignerLabel = "Devnet signer"

        static func buildBadgeAccessibility(_ environment: String) -> String {
            "\(environment) build"
        }

        static let back = "Back"
        static let cancel = "Cancel"
        static let copy = "Copy"
        static let copied = "Copied"
        static let close = "Close"
        static let dismiss = "Dismiss"
        static let done = "Done"
        static let explorer = "Explorer"
        static let inspect = "Inspect"
        static let sent = "Sent"
        static let search = "Search"
        static let clearSearchAccessibilityLabel = "Clear search"
        static let copyAddressAccessibilityLabel = "Copy address"
        static let noSelectorMatchesTitle = "No matches"
        static let noSelectorMatchesMessage = "Try a different search."
        static let noSelectorOptionsTitle = "Nothing to choose"
        static let noSelectorOptionsMessage = "There are no available options for this selection."
        static let selectorLoadingTitle = "Loading options"
        static let selectorLoadingMessage = "Available choices will appear here."
        static let selectorErrorTitle = "Unable to load options"
        static let selectorRetryAction = "Try again"
        static func copyAvailableAccessibility(value: String, action: String) -> String {
            "\(value). \(action) available from context menu."
        }
    }

    enum Empty {
        static let emptyActivityTitle = "No activity yet"
        static let emptyActivityMessage = "Executed proposals and signatures from this Squad will appear here."
        static let emptySignerActivityTitle = "No signatures recorded yet"
        static let emptySignerActivityMessage =
            "Proposals you sign, reject, or execute will appear here across all Squads."
        static let emptyNFTsTitle = "No NFTs"
        static let emptyNFTsMessage = "NFTs received by this vault will appear here."
        static let emptyProposalsTitle = "All clear"
        static let emptyProposalsMessage = "No pending proposals."
        static let emptySquadsTitle = "This signer is a member of no Squads"
        static let emptySquadsMessage =
            "Share this signer's address with a Squad admin to be added. Matching Squads will appear here."
        static let emptyTokensTitle = "No SPL tokens"
        static let emptyTokensMessage = "SPL and Token-2022 holdings will appear here when received."
        static let emptyVaultsTitle = "This Squad has no vaults"
        static let emptyVaultsMessage =
            "A vault is required to hold assets and route transfers. Create one or wait for an admin to add one."
        static let noSignersTitle = "No signers yet"
        static let noSignersMessage =
            "Add a hot wallet or connect a hardware key to start signing."
        static let noLocalSignerTitle = "No signer for this Squad"
        static let noLocalSignerMessage =
            "None of your on-device signers are members of this Squad. Connect or create one whose address is a member."
        static let noRelayInspectionTitle = "Inspection unavailable"
        static let noRelayInspectionMessage =
            "Cosign relay is required for richer proposal inspection. Local decoders ran but found no match for this instruction."
        static let addSignerAction = "Add signer"
        static let configureRelayAction = "Configure relay"
        static let copyAddressAction = "Copy address"
        static let recentActivityAction = "Recent activity"
        static let viewMembersAction = "View members"
    }

    enum Pricing {
        static let unavailableTitle = "USD pricing unavailable"
        static let standardRPCMessage =
            "Connected via standard RPC. Balances are exact; USD values are em-dashes until a Cosign relay is configured."
        static let relayNoQuotesTitle = "Relay returned no quotes"
        static let relayPricingPendingMessage =
            "The relay is reachable but did not return prices for the assets in this vault. USD values render as em-dashes."
    }

    public enum Network {}

    enum Settings {
        static let sectionTitle = "Settings"
        static let screenTitle = "Settings"
        static let signersSection = "Signers"
        static let signersTitle = "Signers"
        static let signersSubtitle = "Manage keys stored on this device."
        static let connectionSection = "Connection & build"
        static let networkTitle = "Network"
        static let networkSubtitle = "Relay connection"
        static let buildVerificationTitle = "Build verification"
        static let buildVerificationSubtitle = "Signed build identity"
        static let aboutSection = "About"
        static let aboutTitle = "About Cosign"
        static let aboutSubtitle = "Version, source, and privacy"

        static func networkStatus(for status: NetworkHealthStatus) -> String {
            switch status {
            case .healthy:
                "Connected"
            case .webSocketDown:
                "Live updates paused"
            case .offline:
                "Offline"
            }
        }

        static func buildStatus(for state: BuildProvenanceState) -> String {
            switch state {
            case .verified:
                "Verified"
            case .developmentBuild:
                "Development build"
            case .failed:
                "Verification failed"
            }
        }
    }

    enum About {
        static let appName = "Cosign"
        static let tagline = "A verifiable signer for Squads v4 multisigs."
        static let versionLabel = "Version"
        static let buildLabel = "Build"
        static let emptyValue = "—"
        static let linksSection = "Links"
        static let sourceTitle = "Source code"
        static let sourceSubtitle = "github.com/hackshare/cosign"
        static let privacyTitle = "Privacy"
        static let privacySubtitle = "How Cosign handles your data"
    }

    enum Demo {
        static let operationsSignerLabel = "Operations"
        static let treasurySignerLabel = "Treasury"
        static let localDevnetSignerLabel = "Local devnet"
        static let emptyPortfolioSignerLabel = "Empty portfolio"
        static let noVaultsSignerLabel = "No-vault member"
        static let detachedSignerLabel = "Detached signer"
    }
}
