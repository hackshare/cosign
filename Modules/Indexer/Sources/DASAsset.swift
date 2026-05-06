import Foundation

public enum DASAssetKind: String, Codable, Sendable {
    case fungible
    case nft
}

public struct DASAsset: Codable, Equatable, Sendable {
    public let id: String
    public let symbol: String?
    public let name: String
    public let tokenAmount: String?
    public let tokenDisplayAmount: String?
    public let decimals: UInt8?
    public let accountAddress: String?
    public let tokenProgramID: String?
    public let imageURI: URL?
    public let kind: DASAssetKind

    public init(
        id: String,
        symbol: String?,
        name: String,
        tokenAmount: String?,
        tokenDisplayAmount: String? = nil,
        decimals: UInt8?,
        accountAddress: String? = nil,
        tokenProgramID: String? = nil,
        imageURI: URL?,
        kind: DASAssetKind
    ) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.tokenAmount = tokenAmount
        self.tokenDisplayAmount = tokenDisplayAmount
        self.decimals = decimals
        self.accountAddress = accountAddress
        self.tokenProgramID = tokenProgramID
        self.imageURI = imageURI
        self.kind = kind
    }

    public func withTokenProgramID(_ tokenProgramID: String?) -> DASAsset {
        DASAsset(
            id: id,
            symbol: symbol,
            name: name,
            tokenAmount: tokenAmount,
            tokenDisplayAmount: tokenDisplayAmount,
            decimals: decimals,
            accountAddress: accountAddress,
            tokenProgramID: tokenProgramID,
            imageURI: imageURI,
            kind: kind
        )
    }
}
