import Foundation

enum LedgerBLEFraming {
    static let apduTag: UInt8 = 0x05

    static func encodeAPDU(_ apdu: Data, mtu: Int) throws -> [Data] {
        guard mtu >= 5 else {
            throw LedgerBLEFramingError.invalidMTU(mtu)
        }
        guard apdu.count <= Int(UInt16.max) else {
            throw LedgerBLEFramingError.payloadTooLarge(apdu.count)
        }

        var frames: [Data] = []
        var sequence: UInt16 = 0
        var offset = apdu.startIndex
        var firstFrame = Data([apduTag])
        firstFrame.appendBigEndian(sequence)
        firstFrame.appendBigEndian(UInt16(apdu.count))

        let firstPayloadLength = min(mtu - 5, apdu.count)
        if firstPayloadLength > 0 {
            let end = apdu.index(offset, offsetBy: firstPayloadLength)
            firstFrame.append(apdu[offset ..< end])
            offset = end
        }
        frames.append(firstFrame)
        sequence += 1

        while offset < apdu.endIndex {
            var frame = Data([apduTag])
            frame.appendBigEndian(sequence)
            let payloadLength = min(mtu - 3, apdu.distance(from: offset, to: apdu.endIndex))
            let end = apdu.index(offset, offsetBy: payloadLength)
            frame.append(apdu[offset ..< end])
            frames.append(frame)
            sequence += 1
            offset = end
        }

        return frames
    }

    static func decodeAPDU(_ frames: [Data]) throws -> Data {
        var expectedSequence: UInt16 = 0
        var expectedLength: Int?
        var apdu = Data()

        for frame in frames {
            guard frame.count >= 3 else {
                throw LedgerBLEFramingError.malformedFrame
            }
            guard frame[frame.startIndex] == apduTag else {
                throw LedgerBLEFramingError.invalidTag(frame[frame.startIndex])
            }

            let sequence = frame.readBigEndianUInt16(at: 1)
            guard sequence == expectedSequence else {
                throw LedgerBLEFramingError.invalidSequence(expected: expectedSequence, actual: sequence)
            }

            var payload = frame.dropFirst(3)
            if sequence == 0 {
                guard payload.count >= 2 else {
                    throw LedgerBLEFramingError.malformedFrame
                }
                expectedLength = Int(payload.readBigEndianUInt16(at: 0))
                payload = payload.dropFirst(2)
            }

            apdu.append(payload)
            if let expectedLength, apdu.count > expectedLength {
                throw LedgerBLEFramingError.payloadTooLarge(apdu.count)
            }

            expectedSequence += 1
        }

        guard let expectedLength else {
            throw LedgerBLEFramingError.incompletePayload(expected: 0, actual: 0)
        }
        guard apdu.count == expectedLength else {
            throw LedgerBLEFramingError.incompletePayload(expected: expectedLength, actual: apdu.count)
        }

        return apdu
    }
}

enum LedgerBLEFramingError: Error, Equatable {
    case invalidMTU(Int)
    case payloadTooLarge(Int)
    case malformedFrame
    case invalidTag(UInt8)
    case invalidSequence(expected: UInt16, actual: UInt16)
    case incompletePayload(expected: Int, actual: Int)
}

private extension Data {
    mutating func appendBigEndian(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    func readBigEndianUInt16(at offset: Int) -> UInt16 {
        (UInt16(self[startIndex + offset]) << 8) | UInt16(self[startIndex + offset + 1])
    }
}
