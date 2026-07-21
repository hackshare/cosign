import Indexer

enum BorshArgumentValue: Equatable {
    case rendered(String)
    case skipped
    case stop
}

/// A pure, positional Borsh reader for on-device instruction argument decoding.
///
/// Renders integer and bool primitives, sizes-and-skips pubkey/string/bytes/128-bit
/// values it can locate but not usefully render, and stops at the first unknown type
/// or exhausted buffer — after either, the byte alignment for later arguments is lost.
struct BorshArgumentReader {
    private static let unsignedByteCounts: [AnchorIDLType: Int] = [
        .u8: 1,
        .u16: 2,
        .u32: 4,
        .u64: 8
    ]

    private static let signedByteCounts: [AnchorIDLType: Int] = [
        .i8: 1,
        .i16: 2,
        .i32: 4,
        .i64: 8
    ]

    private let bytes: [UInt8]
    private var offset: Int

    init(bytes: [UInt8], offset: Int) {
        self.bytes = bytes
        self.offset = offset
    }

    mutating func read(_ type: AnchorIDLType) -> BorshArgumentValue {
        switch type {
        case .bool:
            guard let byte = take(1)?.first else { return .stop }
            return .rendered(byte == 0 ? "false" : "true")
        case .u8, .u16, .u32, .u64:
            return unsigned(Self.unsignedByteCounts[type] ?? 0)
        case .i8, .i16, .i32, .i64:
            return signed(Self.signedByteCounts[type] ?? 0)
        case .u128, .i128:
            return take(16) == nil ? .stop : .skipped
        case .pubkey:
            return take(32) == nil ? .stop : .skipped
        case .string, .bytes:
            guard let length = readLength() else { return .stop }
            return take(length) == nil ? .stop : .skipped
        case .other:
            return .stop
        }
    }

    static func hexToBytes(_ hex: String) -> [UInt8]? {
        InstructionDecoder.bytes(fromHex: hex)
    }

    mutating func readValue(_ type: AnchorIDLType) -> DecodedArgValue? {
        switch type {
        case .bool:
            guard let byte = take(1)?.first else { return nil }
            return .bool(byte != 0)
        case .u8, .u16, .u32, .u64:
            return unsignedValue(Self.unsignedByteCounts[type] ?? 0)
        case .i8, .i16, .i32, .i64:
            return signedValue(Self.signedByteCounts[type] ?? 0)
        case .u128, .i128:
            return take(16) == nil ? nil : .unrendered
        case .pubkey:
            return take(32) == nil ? nil : .unrendered
        case .string, .bytes:
            guard let length = readLength() else { return nil }
            return take(length) == nil ? nil : .unrendered
        case .other:
            return nil
        }
    }

    private mutating func take(_ count: Int) -> ArraySlice<UInt8>? {
        guard count >= 0, offset + count <= bytes.count else { return nil }
        let slice = bytes[offset ..< offset + count]
        offset += count
        return slice
    }

    private mutating func readLength() -> Int? {
        guard let lengthBytes = take(4) else { return nil }
        var value: UInt32 = 0
        for (index, byte) in lengthBytes.enumerated() {
            value |= UInt32(byte) << (index * 8)
        }
        return Int(value)
    }

    private mutating func unsigned(_ count: Int) -> BorshArgumentValue {
        guard let value = unsignedRaw(count) else { return .stop }
        return .rendered(String(value))
    }

    private mutating func signed(_ count: Int) -> BorshArgumentValue {
        guard let value = signedRaw(count) else { return .stop }
        return .rendered(String(value))
    }

    private mutating func unsignedValue(_ count: Int) -> DecodedArgValue? {
        unsignedRaw(count).map(DecodedArgValue.uint)
    }

    private mutating func signedValue(_ count: Int) -> DecodedArgValue? {
        signedRaw(count).map(DecodedArgValue.int)
    }

    private mutating func unsignedRaw(_ count: Int) -> UInt64? {
        guard let bytes = take(count) else { return nil }
        var value: UInt64 = 0
        for (index, byte) in bytes.enumerated() {
            value |= UInt64(byte) << (index * 8)
        }
        return value
    }

    private mutating func signedRaw(_ count: Int) -> Int64? {
        guard let bytes = take(count) else { return nil }
        var magnitude: UInt64 = 0
        for (index, byte) in bytes.enumerated() {
            magnitude |= UInt64(byte) << (index * 8)
        }
        let signBit: UInt64 = 1 << (count * 8 - 1)
        if magnitude & signBit != 0 {
            let mask = count == 8 ? UInt64.max : (UInt64(1) << (count * 8)) - 1
            return Int64(bitPattern: magnitude | ~mask)
        }
        return Int64(magnitude)
    }
}
