import Foundation

public struct YubiKeyAPDUCommand: Equatable, Sendable {
    public let cla: UInt8
    public let instruction: UInt8
    public let parameter1: UInt8
    public let parameter2: UInt8
    public let data: Data

    public init(
        cla: UInt8,
        instruction: UInt8,
        parameter1: UInt8,
        parameter2: UInt8,
        data: Data = Data()
    ) {
        self.cla = cla
        self.instruction = instruction
        self.parameter1 = parameter1
        self.parameter2 = parameter2
        self.data = data
    }

    public var encoded: Data {
        precondition(data.count <= Int(UInt16.max), "YubiKey APDU data length must fit in two bytes.")

        var encoded = Data([cla, instruction, parameter1, parameter2])
        if data.isEmpty {
            return encoded
        }

        if data.count <= Int(UInt8.max) {
            encoded.append(UInt8(data.count))
        } else {
            encoded.append(0x00)
            encoded.appendBigEndian(UInt16(data.count))
        }
        encoded.append(data)
        return encoded
    }
}

public struct YubiKeyAPDUResponse: Equatable, Sendable {
    public let data: Data
    public let status: UInt16

    public init(data: Data = Data(), status: UInt16) {
        self.data = data
        self.status = status
    }

    public init(encoded: Data) throws {
        guard encoded.count >= 2 else {
            throw YubiKeySignerError.malformedResponse
        }

        data = encoded.dropLast(2)
        status = encoded.readBigEndianUInt16(at: encoded.count - 2)
    }

    public func successfulData() throws -> Data {
        if status == YubiKeyPIV.statusOK {
            return data
        }
        if status & 0xFFF0 == YubiKeyPIV.statusPINRetriesRemainingMask {
            throw YubiKeySignerError.invalidPIN(retriesRemaining: Int(status & 0x000F))
        }

        switch status {
        case YubiKeyPIV.statusAuthenticationRequired:
            throw YubiKeySignerError.authenticationRequired
        case YubiKeyPIV.statusPINBlocked:
            throw YubiKeySignerError.pinBlocked
        default:
            throw YubiKeySignerError.deviceStatus(status)
        }
    }
}

public enum YubiKeyPIVSlot: UInt8, Sendable {
    case authentication = 0x9A
    case signature = 0x9C
    case keyManagement = 0x9D
    case cardAuthentication = 0x9E
}

enum YubiKeyPIVAlgorithm: UInt8 {
    case ed25519 = 0xE0
}

enum YubiKeyPIV {
    static let cla: UInt8 = 0x00
    static let claCommandChaining: UInt8 = 0x10
    static let aid = Data([0xA0, 0x00, 0x00, 0x03, 0x08, 0x00, 0x00, 0x10, 0x00])

    static let instructionSelect: UInt8 = 0xA4
    static let instructionVerify: UInt8 = 0x20
    static let instructionAuthenticate: UInt8 = 0x87

    static let statusOK: UInt16 = 0x9000
    static let statusAuthenticationRequired: UInt16 = 0x6982
    static let statusPINBlocked: UInt16 = 0x6983
    static let statusPINRetriesRemainingMask: UInt16 = 0x63C0

    static let maxCommandDataLength = 255

    static func selectCommand() -> YubiKeyAPDUCommand {
        YubiKeyAPDUCommand(
            cla: cla,
            instruction: instructionSelect,
            parameter1: 0x04,
            parameter2: 0x00,
            data: aid
        )
    }

    static func verifyPINCommand(_ pin: String) throws -> YubiKeyAPDUCommand {
        var pinBytes = Data(pin.utf8)
        guard (6 ... 8).contains(pinBytes.count) else {
            throw YubiKeySignerError.invalidPINLength
        }

        while pinBytes.count < 8 {
            pinBytes.append(0xFF)
        }

        return YubiKeyAPDUCommand(
            cla: cla,
            instruction: instructionVerify,
            parameter1: 0x00,
            parameter2: 0x80,
            data: pinBytes
        )
    }

    static func ed25519SignCommands(
        message: Data,
        slot: YubiKeyPIVSlot = .signature
    ) -> [YubiKeyAPDUCommand] {
        chunkedAuthenticateCommands(
            data: authenticateSignData(message),
            slot: slot
        )
    }

    static func authenticateCommand(
        data: Data,
        slot: YubiKeyPIVSlot = .signature
    ) -> YubiKeyAPDUCommand {
        YubiKeyAPDUCommand(
            cla: cla,
            instruction: instructionAuthenticate,
            parameter1: YubiKeyPIVAlgorithm.ed25519.rawValue,
            parameter2: slot.rawValue,
            data: data
        )
    }

    static func parseEd25519Signature(_ responseData: Data) throws -> Data {
        var parser = YubiKeyTLVParser(data: responseData)
        let template = try parser.readExpected(tag: 0x7C)
        try parser.requireEnd()

        var templateParser = YubiKeyTLVParser(data: template)
        let signature = try templateParser.readExpected(tag: 0x82)
        try templateParser.requireEnd()

        guard signature.count == 64 else {
            throw YubiKeySignerError.invalidSignatureLength(signature.count)
        }

        return signature
    }

    private static func authenticateSignData(_ message: Data) -> Data {
        var responseTemplate = Data([0x82, 0x00, 0x81])
        responseTemplate.appendDERLength(message.count)
        responseTemplate.append(message)

        var data = Data([0x7C])
        data.appendDERLength(responseTemplate.count)
        data.append(responseTemplate)
        return data
    }

    private static func chunkedAuthenticateCommands(
        data: Data,
        slot: YubiKeyPIVSlot
    ) -> [YubiKeyAPDUCommand] {
        if data.isEmpty {
            return [authenticateCommand(data: data, slot: slot)]
        }

        var commands: [YubiKeyAPDUCommand] = []
        var offset = data.startIndex

        while offset < data.endIndex {
            let remaining = data.distance(from: offset, to: data.endIndex)
            let chunkLength = min(maxCommandDataLength, remaining)
            let end = data.index(offset, offsetBy: chunkLength)
            let isLast = end == data.endIndex

            commands.append(YubiKeyAPDUCommand(
                cla: isLast ? cla : claCommandChaining,
                instruction: instructionAuthenticate,
                parameter1: YubiKeyPIVAlgorithm.ed25519.rawValue,
                parameter2: slot.rawValue,
                data: data[offset ..< end]
            ))
            offset = end
        }

        return commands
    }
}

public enum YubiKeySignerError: Error, Equatable, Sendable {
    case malformedResponse
    case malformedTLV
    case unexpectedTLVTag(expected: UInt8, actual: UInt8)
    case invalidPINLength
    case invalidPIN(retriesRemaining: Int)
    case pinBlocked
    case authenticationRequired
    case deviceStatus(UInt16)
    case invalidSignatureLength(Int)
    case missingPINProvider
}

private struct YubiKeyTLVParser {
    private let data: Data
    private var offset = 0

    init(data: Data) {
        self.data = data
    }

    mutating func readExpected(tag expectedTag: UInt8) throws -> Data {
        guard offset < data.count else {
            throw YubiKeySignerError.malformedTLV
        }
        let tag = data[data.startIndex + offset]
        guard tag == expectedTag else {
            throw YubiKeySignerError.unexpectedTLVTag(expected: expectedTag, actual: tag)
        }
        offset += 1

        let length = try readLength()
        guard offset + length <= data.count else {
            throw YubiKeySignerError.malformedTLV
        }

        let start = data.startIndex + offset
        let end = start + length
        offset += length
        return data[start ..< end]
    }

    func requireEnd() throws {
        if offset != data.count {
            throw YubiKeySignerError.malformedTLV
        }
    }

    private mutating func readLength() throws -> Int {
        guard offset < data.count else {
            throw YubiKeySignerError.malformedTLV
        }

        let first = data[data.startIndex + offset]
        offset += 1
        if first < 0x80 {
            return Int(first)
        }

        let lengthByteCount = Int(first & 0x7F)
        guard lengthByteCount > 0, lengthByteCount <= 2, offset + lengthByteCount <= data.count else {
            throw YubiKeySignerError.malformedTLV
        }

        var length = 0
        for _ in 0 ..< lengthByteCount {
            length = (length << 8) | Int(data[data.startIndex + offset])
            offset += 1
        }
        return length
    }
}

private extension Data {
    mutating func appendDERLength(_ length: Int) {
        precondition(length <= Int(UInt16.max), "DER length must fit in two bytes.")

        if length < 0x80 {
            append(UInt8(length))
        } else if length <= Int(UInt8.max) {
            append(0x81)
            append(UInt8(length))
        } else {
            append(0x82)
            appendBigEndian(UInt16(length))
        }
    }

    mutating func appendBigEndian(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    func readBigEndianUInt16(at offset: Int) -> UInt16 {
        (UInt16(self[startIndex + offset]) << 8) | UInt16(self[startIndex + offset + 1])
    }
}
