import Indexer

public struct ResolvedMint: Equatable, Sendable {
    public let mint: String
    public let decimals: Int
    public let symbol: String?

    public init(mint: String, decimals: Int, symbol: String?) {
        self.mint = mint
        self.decimals = decimals
        self.symbol = symbol
    }
}

public struct MintResolver: Sendable {
    private let relay: any RelayClient

    public init(relay: any RelayClient) {
        self.relay = relay
    }

    public func resolve(accounts: [String]) async -> [String: ResolvedMint] {
        let unique = Array(Set(accounts))
        guard !unique.isEmpty else {
            return [:]
        }

        return await withTaskGroup(of: (String, ResolvedMint?).self) { group in
            for account in unique {
                group.addTask {
                    await (account, resolveOne(account))
                }
            }

            var result = [String: ResolvedMint]()
            for await (account, resolved) in group {
                if let resolved {
                    result[account] = resolved
                }
            }
            return result
        }
    }

    private func resolveOne(_ account: String) async -> ResolvedMint? {
        guard let response = try? await relay.mintMetadata(for: MintMetadataRequest(account: account)) else {
            return nil
        }
        return ResolvedMint(mint: response.mint, decimals: response.decimals, symbol: response.symbol)
    }
}
