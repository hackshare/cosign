import Foundation

public struct DecodeRegistryRequest: Equatable, Sendable {
    public init() {}
}

public struct DecodeRegistryResponse: Equatable, Sendable {
    public let bundleData: Data
    public let signatureBase64: String

    public init(bundleData: Data, signatureBase64: String) {
        self.bundleData = bundleData
        self.signatureBase64 = signatureBase64
    }
}
