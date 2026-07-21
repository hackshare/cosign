import Foundation

private enum DecodeSpecFieldCodingKeys: String, CodingKey { case name, type }

private enum DecodeSpecEffectCodingKeys: String, CodingKey {
    case when, direction, asset, amount, amountAtLeast, amountAtMost
}

public struct DecodeSpec: Decodable, Equatable, Sendable {
    public enum Mode: String, Decodable, Sendable {
        case bindIdl = "bind-idl"
        case standalone
    }

    public enum Direction: String, Decodable, Sendable {
        case out
        // swiftlint:disable:next identifier_name
        case `in`
    }

    public struct Field: Decodable, Equatable, Sendable {
        public let name: String
        public let type: AnchorIDLType

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DecodeSpecFieldCodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            type = try AnchorIDLType(decoder: container.superDecoder(forKey: .type))
        }
    }

    public struct TemplateVariant: Equatable, Sendable {
        public let when: [String]
        public let text: String

        public init(when: [String], text: String) {
            self.when = when
            self.text = text
        }
    }

    public struct Effect: Decodable, Equatable, Sendable {
        public let when: [String]
        public let direction: Direction
        public let asset: String
        public let amount: String?
        public let amountAtLeast: String?
        public let amountAtMost: String?

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DecodeSpecEffectCodingKeys.self)
            when = try container.decodeIfPresent([String].self, forKey: .when) ?? []
            direction = try container.decode(Direction.self, forKey: .direction)
            asset = try container.decode(String.self, forKey: .asset)
            amount = try container.decodeIfPresent(String.self, forKey: .amount)
            amountAtLeast = try container.decodeIfPresent(String.self, forKey: .amountAtLeast)
            amountAtMost = try container.decodeIfPresent(String.self, forKey: .amountAtMost)
        }
    }

    public let program: String
    public let discriminator: [UInt8]
    public let mode: Mode
    public let bindsIdlHash: String?
    public let layout: [Field]?
    public let action: String
    public let accounts: [String: Int]
    public let template: [TemplateVariant]
    public let effects: [Effect]

    private enum CodingKeys: String, CodingKey {
        case program, discriminator, mode, bindsIdlHash, layout, action, accounts, template, effects
    }

    private struct RawTemplateVariant: Decodable {
        let when: [String]?
        let text: String
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        program = try container.decode(String.self, forKey: .program)
        discriminator = try container.decode([UInt8].self, forKey: .discriminator)
        mode = try container.decode(Mode.self, forKey: .mode)
        bindsIdlHash = try container.decodeIfPresent(String.self, forKey: .bindsIdlHash)
        layout = try container.decodeIfPresent([Field].self, forKey: .layout)
        action = try container.decode(String.self, forKey: .action)
        accounts = try container.decode([String: Int].self, forKey: .accounts)
        effects = try container.decode([Effect].self, forKey: .effects)
        template = try Self.decodeTemplate(from: container)
    }

    private static func decodeTemplate(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [TemplateVariant] {
        if let text = try? container.decode(String.self, forKey: .template) {
            return [TemplateVariant(when: [], text: text)]
        }
        let raw = try container.decode([RawTemplateVariant].self, forKey: .template)
        return raw.map { TemplateVariant(when: $0.when ?? [], text: $0.text) }
    }
}
