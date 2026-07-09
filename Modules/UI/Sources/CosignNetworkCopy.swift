import Foundation
import Indexer

public extension CosignCopy.Network {
    static let screenEyebrow = String(localized: "Relay connection", bundle: .module)
    static let screenTitle = String(localized: "Network", bundle: .module)

    static let relayCardTitle = String(localized: "Cosign relay", bundle: .module)
    static let pinnedTag = String(localized: "Pinned", bundle: .module)
    static let clusterLabel = String(localized: "Cluster", bundle: .module)
    static let hostLabel = String(localized: "Host", bundle: .module)

    static let retryButton = String(localized: "Retry", bundle: .module)

    static let connectionStatesSection = String(localized: "Connection states", bundle: .module)
    static let connectedStateName = String(localized: "Connected", bundle: .module)
    static let connectedStateDetail = String(localized: "Live updates streaming from the relay.", bundle: .module)
    static let pausedStateName = String(localized: "Live updates paused", bundle: .module)
    static let pausedStateDetail = String(localized: "Reconnecting. Showing the last data received.", bundle: .module)
    static let offlineStateName = String(localized: "Offline", bundle: .module)
    static let offlineStateDetail = String(localized: "Can't reach the relay. Showing saved data.", bundle: .module)

    static let selfHostedRowTitle = String(localized: "Use a self-hosted relay", bundle: .module)
    static let selfHostedRowSubtitle = String(
        localized: "Advanced · point Cosign at your own relay build",
        bundle: .module
    )

    static let selfHostedScreenEyebrow = String(localized: "Advanced", bundle: .module)
    static let selfHostedScreenTitle = String(localized: "Self-hosted relay", bundle: .module)
    static let pinnedExplainer =
        String(
            localized: "Endpoint is pinned, not configured. The relay URL is set at build time and shown read-only.",
            bundle: .module
        )

    static let endpointSection = String(localized: "Relay URL", bundle: .module)
    static let endpointPlaceholder = String(localized: "Cosign relay URL", bundle: .module)
    static let showEndpointURL = String(localized: "Show", bundle: .module)
    static let hideEndpointURL = String(localized: "Hide", bundle: .module)
    static let showEndpointURLAccessibilityLabel = String(localized: "Show relay URL", bundle: .module)
    static let hideEndpointURLAccessibilityLabel = String(localized: "Hide relay URL", bundle: .module)
    static let endpointHelp =
        String(
            localized: "Cosign connects through the Cosign relay for decoded inspection and indexing.",
            bundle: .module
        )
    static let savedEndpointSection = String(localized: "Saved endpoint", bundle: .module)
    static let saveEndpointButton = String(localized: "Save relay URL", bundle: .module)
    static let resetToDevnetButton = String(localized: "Reset to pinned relay", bundle: .module)
    static let unableToLoadSavedEndpointTitle = String(localized: "Unable to Load Saved Relay URL", bundle: .module)
    static let settingsErrorTitle = String(localized: "Relay Settings Error", bundle: .module)

    static let reviewInSettingsButton = String(localized: "Review in Settings", bundle: .module)
    static let unableToOpenLinkTitle = String(localized: "Unable to Open Link", bundle: .module)
    static let okButton = String(localized: "OK", bundle: .module)
    static let cancelButton = String(localized: "Cancel", bundle: .module)
    static let updateEndpointPromptTitle = String(localized: "Update Relay URL?", bundle: .module)

    static let provider = String(localized: "Provider", bundle: .module)
    static let cluster = String(localized: "Cluster", bundle: .module)
    static let host = String(localized: "Host", bundle: .module)
    static let credentials = String(localized: "Credentials", bundle: .module)
    static let credentialsIncluded = String(localized: "Included", bundle: .module)
    static let credentialsNoneDetected = String(localized: "None detected", bundle: .module)

    static let demoEnhancedFooter = String(localized: "mainnet · helius · relay enhanced", bundle: .module)
    static let relayEnhancedSuffix = String(localized: "· relay enhanced", bundle: .module)

    static func pinnedFooter(_ environment: String) -> String {
        String(localized: "\(environment) · relay enhanced", bundle: .module)
    }

    static func relayClusterName(_ environment: String) -> String {
        let trimmed = environment.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? String(localized: "Relay", bundle: .module)
            : String(localized: "Solana \(trimmed)", bundle: .module)
    }

    static func statusTitle(for status: NetworkHealthStatus) -> String {
        switch status {
        case .healthy:
            connectedStateName
        case .webSocketDown:
            pausedStateName
        case .offline:
            offlineStateName
        }
    }

    static func statusDetail(for status: NetworkHealthStatus) -> String {
        switch status {
        case .healthy:
            String(localized: "Live updates on", bundle: .module)
        case .webSocketDown:
            pausedStateDetail
        case .offline:
            offlineStateDetail
        }
    }

    static func providerName(_ provider: RPCURLProvider) -> String {
        switch provider {
        case .helius:
            String(localized: "Helius", bundle: .module)
        case .solanaPublic:
            String(localized: "Solana public RPC", bundle: .module)
        case .local:
            String(localized: "Local validator", bundle: .module)
        case .custom:
            String(localized: "Custom RPC", bundle: .module)
        }
    }

    static func clusterName(_ cluster: RPCCluster) -> String {
        switch cluster {
        case .devnet:
            String(localized: "Devnet", bundle: .module)
        case .testnet:
            String(localized: "Testnet", bundle: .module)
        case .mainnetBeta:
            String(localized: "Mainnet Beta", bundle: .module)
        case .local:
            String(localized: "Local", bundle: .module)
        case .unknown:
            String(localized: "Unknown", bundle: .module)
        }
    }

    static func credentialsValue(hasCredentials: Bool) -> String {
        hasCredentials ? credentialsIncluded : credentialsNoneDetected
    }

    static func updateEndpointPromptMessage(for draft: PendingRPCURLDraft) -> String {
        let provider = providerName(draft.rpcURLInfo.provider)
        let cluster = clusterName(draft.rpcURLInfo.cluster)
        let credentials = credentialsValue(hasCredentials: draft.rpcURLInfo.hasCredentials)

        return String(
            localized: """
            A local developer link wants to fill the self-hosted relay URL:

            Provider: \(provider)
            Cluster: \(cluster)
            Credentials: \(credentials)

            \(draft.redactedRPCURLString)

            This will not be saved until you tap \(saveEndpointButton).
            """,
            bundle: .module
        )
    }
}
