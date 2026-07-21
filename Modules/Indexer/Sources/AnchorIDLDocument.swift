import CryptoKit
import Foundation

public enum AnchorIDLType: Equatable, Sendable {
    case bool
    // swiftlint:disable:next identifier_name
    case u8, u16, u32, u64, u128
    // swiftlint:disable:next identifier_name
    case i8, i16, i32, i64, i128
    case pubkey
    case string
    case bytes
    case other

    init(decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let name = try? container.decode(String.self) {
            self = Self.primitivesByName[name] ?? .other
        } else {
            self = .other
        }
    }

    private static let primitivesByName: [String: AnchorIDLType] = [
        "bool": .bool,
        "u8": .u8,
        "u16": .u16,
        "u32": .u32,
        "u64": .u64,
        "u128": .u128,
        "i8": .i8,
        "i16": .i16,
        "i32": .i32,
        "i64": .i64,
        "i128": .i128,
        "pubkey": .pubkey,
        "publicKey": .pubkey,
        "string": .string,
        "bytes": .bytes
    ]
}

public struct AnchorIDLArgument: Equatable, Sendable {
    public let name: String
    public let type: AnchorIDLType
}

public struct AnchorIDLInstruction: Equatable, Sendable {
    public let name: String
    public let discriminator: [UInt8]
    public let arguments: [AnchorIDLArgument]
}

private enum RawArgumentCodingKeys: String, CodingKey {
    case name, type
}

public struct AnchorIDLDocument: Decodable, Equatable, Sendable {
    public let name: String
    public let instructions: [AnchorIDLInstruction]

    private enum CodingKeys: String, CodingKey {
        case name, metadata, instructions
    }

    private struct Metadata: Decodable {
        let name: String?
    }

    private struct RawInstruction: Decodable {
        let name: String
        let discriminator: [UInt8]?
        let args: [RawArgument]?
    }

    private struct RawArgument: Decodable {
        let name: String
        let type: AnchorIDLType

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: RawArgumentCodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            type = try AnchorIDLType(decoder: container.superDecoder(forKey: .type))
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let metadataName = try container.decodeIfPresent(Metadata.self, forKey: .metadata)?.name
        let topLevelName = try container.decodeIfPresent(String.self, forKey: .name)
        name = metadataName ?? topLevelName ?? ""

        let rawInstructions = try container.decodeIfPresent([RawInstruction].self, forKey: .instructions) ?? []
        instructions = rawInstructions.map { raw in
            AnchorIDLInstruction(
                name: raw.name,
                discriminator: raw.discriminator ?? Self.sighash(name: raw.name),
                arguments: (raw.args ?? []).map { AnchorIDLArgument(name: $0.name, type: $0.type) }
            )
        }
    }

    static func sighash(name: String) -> [UInt8] {
        let preimage = "global:" + snakeCased(name)
        let digest = SHA256.hash(data: Data(preimage.utf8))
        return Array(digest.prefix(8))
    }

    static func snakeCased(_ name: String) -> String {
        var result = ""
        for character in name {
            if character.isUppercase {
                if !result.isEmpty {
                    result.append("_")
                }
                result.append(Character(character.lowercased()))
            } else {
                result.append(character)
            }
        }
        return result
    }
}
