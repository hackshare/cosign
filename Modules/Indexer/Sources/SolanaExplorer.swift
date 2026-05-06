import Foundation

public enum SolanaExplorerExecutionLinkKind: Equatable, Sendable {
    case executedTransaction
    case transactionAccount
}

public struct SolanaExplorerExecutionLink: Equatable, Sendable {
    public let kind: SolanaExplorerExecutionLinkKind
    public let url: URL
}

public enum SolanaExplorer {
    public static func transactionURL(signature: String, rpcURL: URL) -> URL? {
        guard !signature.isEmpty else {
            return nil
        }

        return explorerURL(path: "/tx/\(signature)", rpcURL: rpcURL)
    }

    public static func transactionInspectorURL(rpcURL: URL) -> URL? {
        explorerURL(path: "/tx/inspector", rpcURL: rpcURL)
    }

    public static func addressURL(address: String, rpcURL: URL) -> URL? {
        guard !address.isEmpty else {
            return nil
        }

        return explorerURL(path: "/address/\(address)", rpcURL: rpcURL)
    }

    public static func squadsTransactionInspectorURL(transactionAddress: String, rpcURL: URL) -> URL? {
        guard !transactionAddress.isEmpty else {
            return nil
        }

        guard
            let inspectorURL = transactionInspectorURL(rpcURL: rpcURL),
            var components = URLComponents(url: inspectorURL, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "squadsTx", value: transactionAddress))
        components.queryItems = queryItems
        return components.url
    }

    public static func executedProposalLink(
        executionSignature: String?,
        transactionAddress: String?,
        rpcURL: URL
    ) -> SolanaExplorerExecutionLink? {
        if let executionSignature {
            let executionURL = transactionURL(signature: executionSignature, rpcURL: rpcURL)
            if let executionURL {
                return SolanaExplorerExecutionLink(kind: .executedTransaction, url: executionURL)
            }
        }

        guard let transactionAddress,
              let url = addressURL(address: transactionAddress, rpcURL: rpcURL)
        else {
            return nil
        }

        return SolanaExplorerExecutionLink(kind: .transactionAccount, url: url)
    }

    private static func explorerURL(path: String, rpcURL: URL) -> URL? {
        let info = NetworkSettingsStore.rpcURLInfo(for: rpcURL)
        guard let queryItems = clusterQueryItems(for: info, rpcURL: rpcURL) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "explorer.solana.com"
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }

    private static func clusterQueryItems(for info: RPCURLInfo, rpcURL: URL) -> [URLQueryItem]? {
        switch info.cluster {
        case .devnet:
            return [URLQueryItem(name: "cluster", value: "devnet")]
        case .testnet:
            return [URLQueryItem(name: "cluster", value: "testnet")]
        case .mainnetBeta:
            return [URLQueryItem(name: "cluster", value: "mainnet-beta")]
        case .local:
            return customClusterQueryItems(for: rpcURL)
        case .unknown:
            guard canShareCustomRPCURL(info: info, rpcURL: rpcURL) else {
                return nil
            }
            return customClusterQueryItems(for: rpcURL)
        }
    }

    private static func canShareCustomRPCURL(info: RPCURLInfo, rpcURL: URL) -> Bool {
        guard !info.hasCredentials, rpcURL.user == nil, rpcURL.password == nil else {
            return false
        }

        guard let components = URLComponents(url: rpcURL, resolvingAgainstBaseURL: false) else {
            return false
        }

        let hasQuery = components.queryItems?.isEmpty == false
        let path = components.percentEncodedPath
        return !hasQuery && (path.isEmpty || path == "/")
    }

    private static func customClusterQueryItems(for rpcURL: URL) -> [URLQueryItem] {
        [
            URLQueryItem(name: "cluster", value: "custom"),
            URLQueryItem(name: "customUrl", value: rpcURL.absoluteString)
        ]
    }
}
