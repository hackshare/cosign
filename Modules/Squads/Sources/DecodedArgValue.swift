import Indexer

public enum DecodedArgValue: Equatable, Sendable {
    case uint(UInt64)
    case int(Int64)
    case bool(Bool)
    case unrendered

    public var rendered: String? {
        switch self {
        case let .uint(value): String(value)
        case let .int(value): String(value)
        case let .bool(value): value ? "true" : "false"
        case .unrendered: nil
        }
    }
}

/// Decodes named Borsh arguments positionally, stopping at the first field that cannot
/// be sized (so later fields are absent rather than misaligned).
public func decodeArguments(
    bytes: [UInt8],
    offset: Int,
    fields: [(name: String, type: AnchorIDLType)]
) -> [String: DecodedArgValue] {
    var reader = BorshArgumentReader(bytes: bytes, offset: offset)
    var result = [String: DecodedArgValue]()
    for field in fields {
        guard let value = reader.readValue(field.type) else { break }
        result[field.name] = value
    }
    return result
}
