import Foundation

public struct DecodeRegistryBundle: Decodable, Equatable, Sendable {
    public let schema: Int
    public let keyId: String
    public let specs: [DecodeSpec]
}
