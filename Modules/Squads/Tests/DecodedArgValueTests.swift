import Indexer
import Testing
@testable import Squads

struct DecodedArgValueTests {
    @Test func readsTypedUnsignedAndBool() {
        var reader = BorshArgumentReader(bytes: [136, 19, 0, 0, 0, 0, 0, 0, 1], offset: 0)
        #expect(reader.readValue(.u64) == .uint(5000))
        #expect(reader.readValue(.bool) == .bool(true))
    }

    @Test func readsTypedSignedNegative() {
        var reader = BorshArgumentReader(bytes: [255, 255, 255, 255], offset: 0)
        #expect(reader.readValue(.i32) == .int(-1))
    }

    @Test func pubkeyAndStringAreUnrenderedButConsumed() {
        var reader = BorshArgumentReader(bytes: Array(repeating: 7, count: 32) + [2, 0, 0, 0, 65, 66, 9], offset: 0)
        #expect(reader.readValue(.pubkey) == .unrendered)
        #expect(reader.readValue(.string) == .unrendered)
        #expect(reader.readValue(.u8) == .uint(9))
    }

    @Test func otherTypeStops() {
        var reader = BorshArgumentReader(bytes: [1, 2, 3, 4], offset: 0)
        #expect(reader.readValue(.other) == nil)
    }

    @Test func decodeArgumentsBuildsNamedMap() {
        // amount=1000000 (u64), aToB=true (bool), then a u64 after.
        let bytes = BorshArgumentReader.hexToBytes("40420f0000000000" + "01" + "0100000000000000")!
        let args = decodeArguments(
            bytes: bytes,
            offset: 0,
            fields: [("amount", .u64), ("aToB", .bool), ("tail", .u64)]
        )
        #expect(args["amount"] == .uint(1_000_000))
        #expect(args["aToB"] == .bool(true))
        #expect(args["tail"] == .uint(1))
    }

    @Test func decodeArgumentsStopsAtUnknownType() {
        let bytes: [UInt8] = [1]
        let args = decodeArguments(bytes: bytes, offset: 0, fields: [("flag", .u8), ("blob", .other), ("tail", .u8)])
        #expect(args["flag"] == .uint(1))
        #expect(args["blob"] == nil)
        #expect(args["tail"] == nil)
    }
}
