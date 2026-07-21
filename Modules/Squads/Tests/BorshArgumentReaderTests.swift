import Indexer
import Testing
@testable import Squads

struct BorshArgumentReaderTests {
    @Test func readsUnsignedInteger() {
        // 5000 as u64 little-endian.
        var reader = BorshArgumentReader(bytes: [136, 19, 0, 0, 0, 0, 0, 0], offset: 0)
        #expect(reader.read(.u64) == .rendered("5000"))
    }

    @Test func readsSignedNegativeInteger() {
        // -1 as i32 little-endian.
        var reader = BorshArgumentReader(bytes: [255, 255, 255, 255], offset: 0)
        #expect(reader.read(.i32) == .rendered("-1"))
    }

    @Test func readsBool() {
        var reader = BorshArgumentReader(bytes: [1], offset: 0)
        #expect(reader.read(.bool) == .rendered("true"))
    }

    @Test func readsBoolAtNonZeroOffset() {
        var reader = BorshArgumentReader(bytes: [7, 1], offset: 0)
        #expect(reader.read(.u8) == .rendered("7"))
        #expect(reader.read(.bool) == .rendered("true"))
    }

    @Test func skipsPubkeyAndAdvances() {
        var reader = BorshArgumentReader(bytes: Array(repeating: 7, count: 40), offset: 0)
        #expect(reader.read(.pubkey) == .skipped)
        // 32 consumed, 8 left → a u64 still reads.
        #expect(reader.read(.u64) == .rendered("506381209866536711"))
    }

    @Test func skipsStringViaLengthPrefix() {
        // length 2 (u32 LE) + two bytes, then a u8 = 9.
        var reader = BorshArgumentReader(bytes: [2, 0, 0, 0, 65, 66, 9], offset: 0)
        #expect(reader.read(.string) == .skipped)
        #expect(reader.read(.u8) == .rendered("9"))
    }

    @Test func stopsOnOtherType() {
        var reader = BorshArgumentReader(bytes: [1, 2, 3, 4], offset: 0)
        #expect(reader.read(.other) == .stop)
    }

    @Test func stopsWhenExhausted() {
        var reader = BorshArgumentReader(bytes: [1, 2], offset: 0)
        #expect(reader.read(.u64) == .stop)
    }
}
