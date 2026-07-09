import Foundation
import Indexer
import Provenance

public enum CosignCopy {}

extension CosignCopy {
    public enum Common {
        static let appName = String(localized: "cosign", bundle: .module)
        public static let devnetSeedSignerLabel = String(localized: "Devnet signer", bundle: .module)

        static func buildBadgeAccessibility(_ environment: String) -> String {
            String(localized: "\(environment) build", bundle: .module)
        }

        static let back = String(localized: "Back", bundle: .module)
        static let cancel = String(localized: "Cancel", bundle: .module)
        static let copy = String(localized: "Copy", bundle: .module)
        static let copied = String(localized: "Copied", bundle: .module)
        static let close = String(localized: "Close", bundle: .module)
        static let dismiss = String(localized: "Dismiss", bundle: .module)
        static let done = String(localized: "Done", bundle: .module)
        static let explorer = String(localized: "Explorer", bundle: .module)
        static let inspect = String(localized: "Inspect", bundle: .module)
        static let sent = String(localized: "Sent", bundle: .module)
        static let search = String(localized: "Search", bundle: .module)
        static let clearSearchAccessibilityLabel = String(localized: "Clear search", bundle: .module)
        static let copyAddressAccessibilityLabel = String(localized: "Copy address", bundle: .module)
        static let noSelectorMatchesTitle = String(localized: "No matches", bundle: .module)
        static let noSelectorMatchesMessage = String(localized: "Try a different search.", bundle: .module)
        static let noSelectorOptionsTitle = String(localized: "Nothing to choose", bundle: .module)
        static let noSelectorOptionsMessage = String(
            localized: "There are no available options for this selection.",
            bundle: .module
        )
        static let selectorLoadingTitle = String(localized: "Loading options", bundle: .module)
        static let selectorLoadingMessage = String(localized: "Available choices will appear here.", bundle: .module)
        static let selectorErrorTitle = String(localized: "Unable to load options", bundle: .module)
        static let selectorRetryAction = String(localized: "Try again", bundle: .module)
        static func copyAvailableAccessibility(value: String, action: String) -> String {
            String(localized: "\(value). \(action) available from context menu.", bundle: .module)
        }
    }

    enum Empty {
        static let emptyActivityTitle = String(localized: "No activity yet", bundle: .module)
        static let emptyActivityMessage = String(
            localized: "Executed proposals and signatures from this Squad will appear here.",
            bundle: .module
        )
        static let emptySignerActivityTitle = String(localized: "No signatures recorded yet", bundle: .module)
        static let emptySignerActivityMessage =
            String(
                localized: "Proposals you sign, reject, or execute will appear here across all Squads.",
                bundle: .module
            )
        static let emptyNFTsTitle = String(localized: "No NFTs", bundle: .module)
        static let emptyNFTsMessage = String(
            localized: "NFTs received by this vault will appear here.",
            bundle: .module
        )
        static let emptyProposalsTitle = String(localized: "All clear", bundle: .module)
        static let emptyProposalsMessage = String(localized: "No pending proposals.", bundle: .module)
        static let emptySquadsTitle = String(localized: "No squads yet", bundle: .module)
        static let emptySquadsMessage =
            String(
                localized: "Create a Squad to hold funds and co-sign proposals, or share your address so an admin can add you to theirs.",
                bundle: .module
            )
        static let emptyTokensTitle = String(localized: "No SPL tokens", bundle: .module)
        static let emptyTokensMessage = String(
            localized: "SPL and Token-2022 holdings will appear here when received.",
            bundle: .module
        )
        static let emptyVaultsTitle = String(localized: "This Squad has no vaults", bundle: .module)
        static let emptyVaultsMessage =
            String(
                localized: "A vault is required to hold assets and route transfers. Create one or wait for an admin to add one.",
                bundle: .module
            )
        static let noSignersTitle = String(localized: "No signers yet", bundle: .module)
        static let noSignersMessage =
            String(localized: "Add a hot wallet or connect a hardware key to start signing.", bundle: .module)
        static let noLocalSignerTitle = String(localized: "No signer for this Squad", bundle: .module)
        static let noLocalSignerMessage =
            String(
                localized: "None of your on-device signers are members of this Squad. Connect or create one whose address is a member.",
                bundle: .module
            )
        static let noRelayInspectionTitle = String(localized: "Inspection unavailable", bundle: .module)
        static let noRelayInspectionMessage =
            String(
                localized: "Cosign relay is required for richer proposal inspection. Local decoders ran but found no match for this instruction.",
                bundle: .module
            )
        static let addSignerAction = String(localized: "Add signer", bundle: .module)
        static let configureRelayAction = String(localized: "Configure relay", bundle: .module)
        static let copyAddressAction = String(localized: "Copy address", bundle: .module)
        static let recentActivityAction = String(localized: "Recent activity", bundle: .module)
        static let viewMembersAction = String(localized: "View members", bundle: .module)
    }

    enum Pricing {
        static let unavailableTitle = String(localized: "USD pricing unavailable", bundle: .module)
        static let standardRPCMessage =
            String(
                localized: "Connected via standard RPC. Balances are exact; USD values are em-dashes until a Cosign relay is configured.",
                bundle: .module
            )
        static let relayNoQuotesTitle = String(localized: "Relay returned no quotes", bundle: .module)
        static let relayPricingPendingMessage =
            String(
                localized: "The relay is reachable but did not return prices for the assets in this vault. USD values render as em-dashes.",
                bundle: .module
            )
    }

    public enum Network {}

    enum Settings {
        static let sectionTitle = String(localized: "Settings", bundle: .module)
        static let screenTitle = String(localized: "Settings", bundle: .module)
        static let signersSection = String(localized: "Signers", bundle: .module)
        static let signersTitle = String(localized: "Signers", bundle: .module)
        static let signersSubtitle = String(localized: "Manage keys stored on this device.", bundle: .module)
        static let connectionSection = String(localized: "Connection & build", bundle: .module)
        static let networkTitle = String(localized: "Network", bundle: .module)
        static let networkSubtitle = String(localized: "Relay connection", bundle: .module)
        static let buildVerificationTitle = String(localized: "Build verification", bundle: .module)
        static let buildVerificationSubtitle = String(localized: "Signed build identity", bundle: .module)
        static let aboutSection = String(localized: "About", bundle: .module)
        static let aboutTitle = String(localized: "About Cosign", bundle: .module)
        static let aboutSubtitle = String(localized: "Version, source, and privacy", bundle: .module)

        static func networkStatus(for status: NetworkHealthStatus) -> String {
            switch status {
            case .healthy:
                String(localized: "Connected", bundle: .module)
            case .webSocketDown:
                String(localized: "Live updates paused", bundle: .module)
            case .offline:
                String(localized: "Offline", bundle: .module)
            }
        }

        static func buildStatus(for state: BuildProvenanceState) -> String {
            switch state {
            case .verified:
                String(localized: "Verified", bundle: .module)
            case .developmentBuild:
                String(localized: "Development build", bundle: .module)
            case .failed:
                String(localized: "Verification failed", bundle: .module)
            }
        }
    }

    enum About {
        static let appName = String(localized: "Cosign", bundle: .module)
        static let tagline = String(
            localized: "A verifiable signer for Solana Squads v4 multisigs. Every proposal is decoded on your device.",
            bundle: .module
        )
        static let versionLabel = String(localized: "Version", bundle: .module)
        static let buildLabel = String(localized: "Build", bundle: .module)
        static let emptyValue = String(localized: "—", bundle: .module)
        static let linksSection = String(localized: "Links", bundle: .module)
        static let sourceTitle = String(localized: "Source code", bundle: .module)
        static let sourceSubtitle = "github.com/hackshare/cosign"
        static let privacyTitle = String(localized: "Privacy", bundle: .module)
        static let privacySubtitle = String(localized: "How Cosign handles your data", bundle: .module)
    }

    enum Demo {
        static let operationsSignerLabel = String(localized: "Operations", bundle: .module)
        static let treasurySignerLabel = String(localized: "Treasury", bundle: .module)
        static let localDevnetSignerLabel = String(localized: "Local devnet", bundle: .module)
        static let emptyPortfolioSignerLabel = String(localized: "Empty portfolio", bundle: .module)
        static let noVaultsSignerLabel = String(localized: "No-vault member", bundle: .module)
        static let detachedSignerLabel = String(localized: "Detached signer", bundle: .module)
    }
}
