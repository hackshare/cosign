import Foundation

public struct MintMetadataRequest: Equatable, Sendable {
    public let account: String
    public init(account: String) {
        self.account = account
    }
}

public struct MintMetadataResponse: Decodable, Equatable, Sendable {
    public let account: String
    public let mint: String
    public let decimals: Int
    public let symbol: String?

    public init(account: String, mint: String, decimals: Int, symbol: String?) {
        self.account = account
        self.mint = mint
        self.decimals = decimals
        self.symbol = symbol
    }
}
