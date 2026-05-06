import Foundation

public struct LedgerDerivationPath: Equatable, Sendable {
    public let components: [UInt32]

    public static let defaultSolana = LedgerDerivationPath(components: [
        hardened(44),
        hardened(501),
        hardened(0),
        hardened(0)
    ])

    public init(components: [UInt32]) {
        precondition(components.count <= Int(UInt8.max), "Ledger derivation paths support at most 255 components.")
        self.components = components
    }

    public static func hardened(_ component: UInt32) -> UInt32 {
        component | 0x8000_0000
    }

    public var serialized: Data {
        var data = Data([UInt8(components.count)])
        for component in components {
            data.appendBigEndian(component)
        }
        return data
    }
}

public struct LedgerAPDUCommand: Equatable, Sendable {
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
        precondition(data.count <= Int(UInt8.max), "APDU data length must fit in one byte.")
        var encoded = Data([cla, instruction, parameter1, parameter2, UInt8(data.count)])
        encoded.append(data)
        return encoded
    }
}

public struct LedgerAPDUResponse: Equatable, Sendable {
    public let data: Data
    public let status: UInt16

    public init(data: Data = Data(), status: UInt16) {
        self.data = data
        self.status = status
    }

    public init(encoded: Data) throws {
        guard encoded.count >= 2 else {
            throw LedgerSignerError.malformedResponse
        }

        data = encoded.dropLast(2)
        status = encoded.readBigEndianUInt16(at: encoded.count - 2)
    }

    public func successfulData() throws -> Data {
        switch status {
        case LedgerSolanaAPDU.statusOK:
            return data
        case LedgerSolanaAPDU.statusBlindSignatureRequired:
            throw LedgerSignerError.blindSigningRequired
        default:
            throw LedgerSignerError.deviceStatus(status)
        }
    }
}

public struct LedgerSolanaAppConfiguration: Equatable, Sendable {
    public let blindSigningEnabled: Bool
    public let pubkeyDisplayMode: UInt8
    public let version: String
}

public enum LedgerSolanaAPDU {
    public static let cla: UInt8 = 0xE0
    public static let instructionGetConfiguration: UInt8 = 0x04
    public static let instructionGetAddress: UInt8 = 0x05
    public static let instructionSignTransaction: UInt8 = 0x06

    public static let p1NonConfirm: UInt8 = 0x00
    public static let p1Confirm: UInt8 = 0x01
    public static let p2Extend: UInt8 = 0x01
    public static let p2More: UInt8 = 0x02

    public static let statusOK: UInt16 = 0x9000
    public static let statusBlindSignatureRequired: UInt16 = 0x6808

    static let maxPayloadLength = 255

    public static func appConfigurationCommand() -> LedgerAPDUCommand {
        LedgerAPDUCommand(
            cla: cla,
            instruction: instructionGetConfiguration,
            parameter1: p1NonConfirm,
            parameter2: 0
        )
    }

    public static func addressCommand(
        path: LedgerDerivationPath = .defaultSolana,
        displayOnDevice: Bool = false
    ) -> LedgerAPDUCommand {
        LedgerAPDUCommand(
            cla: cla,
            instruction: instructionGetAddress,
            parameter1: displayOnDevice ? p1Confirm : p1NonConfirm,
            parameter2: 0,
            data: path.serialized
        )
    }

    public static func signTransactionCommands(
        path: LedgerDerivationPath = .defaultSolana,
        message: Data
    ) -> [LedgerAPDUCommand] {
        var payload = Data([1])
        payload.append(path.serialized)
        payload.append(message)
        return chunkedCommands(
            instruction: instructionSignTransaction,
            parameter1: p1Confirm,
            payload: payload
        )
    }

    public static func parseAppConfiguration(_ responseData: Data) throws -> LedgerSolanaAppConfiguration {
        guard responseData.count >= 5 else {
            throw LedgerSignerError.malformedResponse
        }

        return LedgerSolanaAppConfiguration(
            blindSigningEnabled: responseData[responseData.startIndex] != 0,
            pubkeyDisplayMode: responseData[responseData.startIndex + 1],
            version: [
                responseData[responseData.startIndex + 2],
                responseData[responseData.startIndex + 3],
                responseData[responseData.startIndex + 4]
            ].map(String.init).joined(separator: ".")
        )
    }

    public static func parseAddress(_ responseData: Data) throws -> Data {
        guard responseData.count == 32 else {
            throw LedgerSignerError.invalidAddressLength(responseData.count)
        }

        return responseData
    }

    static func chunkedCommands(
        instruction: UInt8,
        parameter1: UInt8,
        payload: Data
    ) -> [LedgerAPDUCommand] {
        var commands: [LedgerAPDUCommand] = []
        var offset = payload.startIndex
        var parameter2: UInt8 = 0

        while payload.distance(from: offset, to: payload.endIndex) > maxPayloadLength {
            let end = payload.index(offset, offsetBy: maxPayloadLength)
            commands.append(LedgerAPDUCommand(
                cla: cla,
                instruction: instruction,
                parameter1: parameter1,
                parameter2: parameter2 | p2More,
                data: payload[offset ..< end]
            ))
            offset = end
            parameter2 |= p2Extend
        }

        commands.append(LedgerAPDUCommand(
            cla: cla,
            instruction: instruction,
            parameter1: parameter1,
            parameter2: parameter2,
            data: payload[offset ..< payload.endIndex]
        ))
        return commands
    }
}

enum LedgerSignerError: Error, Equatable {
    case malformedResponse
    case blindSigningRequired
    case deviceStatus(UInt16)
    case addressMismatch(expected: Data, actual: Data)
    case invalidAddressLength(Int)
    case invalidSignatureLength(Int)
}

private extension Data {
    mutating func appendBigEndian(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    func readBigEndianUInt16(at offset: Int) -> UInt16 {
        (UInt16(self[startIndex + offset]) << 8) | UInt16(self[startIndex + offset + 1])
    }
}
