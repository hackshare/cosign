import Indexer

public extension CosignCopy.Network {
    static let screenEyebrow = "RPC endpoint"
    static let screenTitle = "Network"
    static let current = "Current"
    static let endpointSection = "Endpoint"
    static let endpointPlaceholder = "Solana RPC or Cosign relay URL"
    static let showEndpointURL = "Show"
    static let hideEndpointURL = "Hide"
    static let showEndpointURLAccessibilityLabel = "Show Network Endpoint"
    static let hideEndpointURLAccessibilityLabel = "Hide Network Endpoint"
    static let endpointHelp =
        "Cosign can use a standard Solana RPC URL. " +
        "If the endpoint is a Cosign relay, enhanced inspection and indexing features are enabled automatically."
    static let savedEndpointSection = "Saved Endpoint"
    static let saveEndpointButton = "Save Network Endpoint"
    static let resetToDevnetButton = "Reset to Devnet"
    static let unableToLoadSavedEndpointTitle = "Unable to Load Saved Network Endpoint"
    static let settingsErrorTitle = "Network Settings Error"
    static let reviewInSettingsButton = "Review in Settings"
    static let unableToOpenLinkTitle = "Unable to Open Link"
    static let okButton = "OK"
    static let cancelButton = "Cancel"
    static let updateEndpointPromptTitle = "Update Network Endpoint?"

    static let provider = "Provider"
    static let cluster = "Cluster"
    static let host = "Host"
    static let credentials = "Credentials"
    static let credentialsIncluded = "Included"
    static let credentialsNoneDetected = "None detected"

    static let demoEnhancedFooter = "mainnet · helius · relay enhanced"

    static func pinnedFooter(_ environment: String) -> String {
        "\(environment) · relay enhanced"
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
        A local developer link wants to fill this network endpoint in Settings:

        Provider: \(provider)
        Cluster: \(cluster)
        Credentials: \(credentials)

        \(draft.redactedRPCURLString)

        This will not be saved until you tap \(saveEndpointButton).
        """
    }
}
