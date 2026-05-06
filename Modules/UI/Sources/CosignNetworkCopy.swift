import Indexer

public extension CosignCopy.Network {
    static let screenEyebrow = "Relay connection"
    static let screenTitle = "Network"

    static let relayCardTitle = "Cosign relay"
    static let pinnedTag = "Pinned"
    static let clusterLabel = "Cluster"
    static let hostLabel = "Host"

    static let retryButton = "Retry"

    static let connectionStatesSection = "Connection states"
    static let connectedStateName = "Connected"
    static let connectedStateDetail = "Live updates streaming from the relay."
    static let pausedStateName = "Live updates paused"
    static let pausedStateDetail = "Reconnecting. Showing the last data received."
    static let offlineStateName = "Offline"
    static let offlineStateDetail = "Can't reach the relay. Showing saved data."

    static let selfHostedRowTitle = "Use a self-hosted relay"
    static let selfHostedRowSubtitle = "Advanced · point Cosign at your own relay build"

    static let selfHostedScreenEyebrow = "Advanced"
    static let selfHostedScreenTitle = "Self-hosted relay"
    static let pinnedExplainer =
        "Endpoint is pinned, not configured. The relay URL is set at build time and shown read-only."

    static let endpointSection = "Relay URL"
    static let endpointPlaceholder = "Cosign relay URL"
    static let showEndpointURL = "Show"
    static let hideEndpointURL = "Hide"
    static let showEndpointURLAccessibilityLabel = "Show relay URL"
    static let hideEndpointURLAccessibilityLabel = "Hide relay URL"
    static let endpointHelp =
        "Cosign connects through the Cosign relay for decoded inspection and indexing."
    static let savedEndpointSection = "Saved endpoint"
    static let saveEndpointButton = "Save relay URL"
    static let resetToDevnetButton = "Reset to pinned relay"
    static let unableToLoadSavedEndpointTitle = "Unable to Load Saved Relay URL"
    static let settingsErrorTitle = "Relay Settings Error"

    static let reviewInSettingsButton = "Review in Settings"
    static let unableToOpenLinkTitle = "Unable to Open Link"
    static let okButton = "OK"
    static let cancelButton = "Cancel"
    static let updateEndpointPromptTitle = "Update Relay URL?"

    static let provider = "Provider"
    static let cluster = "Cluster"
    static let host = "Host"
    static let credentials = "Credentials"
    static let credentialsIncluded = "Included"
    static let credentialsNoneDetected = "None detected"

    static let demoEnhancedFooter = "mainnet · helius · relay enhanced"
    static let relayEnhancedSuffix = "· relay enhanced"

    static func pinnedFooter(_ environment: String) -> String {
        "\(environment) · relay enhanced"
    }

    static func relayClusterName(_ environment: String) -> String {
        let trimmed = environment.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Relay" : "Solana \(trimmed)"
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
            "Live updates on"
        case .webSocketDown:
            pausedStateDetail
        case .offline:
            offlineStateDetail
        }
    }

    static func providerName(_ provider: RPCURLProvider) -> String {
        switch provider {
        case .helius:
            "Helius"
        case .solanaPublic:
            "Solana public RPC"
        case .local:
            "Local validator"
        case .custom:
            "Custom RPC"
        }
    }

    static func clusterName(_ cluster: RPCCluster) -> String {
        switch cluster {
        case .devnet:
            "Devnet"
        case .testnet:
            "Testnet"
        case .mainnetBeta:
            "Mainnet Beta"
        case .local:
            "Local"
        case .unknown:
            "Unknown"
        }
    }

    static func credentialsValue(hasCredentials: Bool) -> String {
        hasCredentials ? credentialsIncluded : credentialsNoneDetected
    }

    static func updateEndpointPromptMessage(for draft: PendingRPCURLDraft) -> String {
        let provider = providerName(draft.rpcURLInfo.provider)
        let cluster = clusterName(draft.rpcURLInfo.cluster)
        let credentials = credentialsValue(hasCredentials: draft.rpcURLInfo.hasCredentials)

        return """
        A local developer link wants to fill the self-hosted relay URL:

        Provider: \(provider)
        Cluster: \(cluster)
        Credentials: \(credentials)

        \(draft.redactedRPCURLString)

        This will not be saved until you tap \(saveEndpointButton).
        """
    }
}
