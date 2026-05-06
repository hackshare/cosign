import Core
import Foundation
import Testing
@testable import Signers

struct YubiKeySignerTests {
    @Test func buildsSelectAndVerifyPINCommands() throws {
        #expect(YubiKeyPIV.selectCommand().encoded == Data([
            0x00, 0xA4, 0x04, 0x00, 0x09,
            0xA0, 0x00, 0x00, 0x03, 0x08, 0x00, 0x00, 0x10, 0x00
        ]))

        #expect(try YubiKeyPIV.verifyPINCommand("123456").encoded == Data([
            0x00, 0x20, 0x00, 0x80, 0x08,
            0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0xFF, 0xFF
        ]))
        #expect(try YubiKeyPIV.verifyPINCommand("12345678").data == Data("12345678".utf8))
        #expect(throws: YubiKeySignerError.invalidPINLength) {
            try YubiKeyPIV.verifyPINCommand("12345")
        }
    }

    @Test func chainsLongEd25519SignCommands() {
        let commands = YubiKeyPIV.ed25519SignCommands(message: Data(repeating: 0xAB, count: 300))

        #expect(commands.count == 2)
        #expect(commands.map(\.cla) == [YubiKeyPIV.claCommandChaining, YubiKeyPIV.cla])
        #expect(commands.map(\.data.count) == [255, 55])
        #expect(commands[0].data.prefix(10) == Data([
            0x7C, 0x82, 0x01, 0x32,
            0x82, 0x00,
            0x81, 0x82, 0x01, 0x2C
        ]))
    }

    @Test func parsesYubiKeyResponses() throws {
        let response = try YubiKeyAPDUResponse(encoded: Data([0xAA, 0xBB, 0x90, 0x00]))

        #expect(try response.successfulData() == Data([0xAA, 0xBB]))

        let invalidPINResponse = try YubiKeyAPDUResponse(encoded: Data([0x63, 0xC3]))
        #expect(throws: YubiKeySignerError.invalidPIN(retriesRemaining: 3)) {
            try invalidPINResponse.successfulData()
        }

        let blockedPINResponse = try YubiKeyAPDUResponse(encoded: Data([0x69, 0x83]))
        #expect(throws: YubiKeySignerError.pinBlocked) {
            try blockedPINResponse.successfulData()
        }
    }

    @Test func parsesEd25519SignatureResponse() throws {
        let signature = Data(repeating: 0xCC, count: 64)

        #expect(try YubiKeyPIV.parseEd25519Signature(Self.signatureResponse(signature)) == signature)
        #expect(throws: YubiKeySignerError.invalidSignatureLength(63)) {
            try YubiKeyPIV.parseEd25519Signature(Self.signatureResponse(Data(repeating: 0xCC, count: 63)))
        }
    }

    @Test func yubiKeySignerRequiresTransport() async throws {
        let signer = YubiKeySigner(
            label: "YubiKey",
            pubkey: Data(repeating: 1, count: 32),
            pinProvider: { "123456" }
        )

        await #expect(throws: SignerError.self) {
            _ = try await signer.sign(message: Data([1, 2, 3]))
        }
    }

    @Test func yubiKeySignerRequiresPINProvider() async throws {
        let transport = RecordingYubiKeyTransport(responses: [])
        let signer = YubiKeySigner(
            label: "YubiKey",
            pubkey: Data(repeating: 1, count: 32),
            transport: transport
        )

        await #expect(throws: SignerError.self) {
            _ = try await signer.sign(message: Data([1, 2, 3]))
        }
    }

    @Test func yubiKeySignerSubmitsPIVSignCommands() async throws {
        let signature = Data(repeating: 0xCC, count: 64)
        let transport = RecordingYubiKeyTransport(responses: [
            YubiKeyAPDUResponse(status: YubiKeyPIV.statusOK),
            YubiKeyAPDUResponse(status: YubiKeyPIV.statusOK),
            YubiKeyAPDUResponse(status: YubiKeyPIV.statusOK),
            YubiKeyAPDUResponse(data: Self.signatureResponse(signature), status: YubiKeyPIV.statusOK)
        ])
        let signer = YubiKeySigner(
            label: "YubiKey",
            pubkey: Data(repeating: 1, count: 32),
            transport: transport,
            pinProvider: { "123456" }
        )

        let submittedSignature = try await signer.sign(message: Data(repeating: 0xAB, count: 300))
        let commands = await transport.recordedCommands

        #expect(submittedSignature == signature)
        #expect(commands.map(\.instruction) == [
            YubiKeyPIV.instructionSelect,
            YubiKeyPIV.instructionVerify,
            YubiKeyPIV.instructionAuthenticate,
            YubiKeyPIV.instructionAuthenticate
        ])
        #expect(commands[2].cla == YubiKeyPIV.claCommandChaining)
        #expect(commands[3].cla == YubiKeyPIV.cla)
        #expect(commands[3].parameter2 == YubiKeyPIVSlot.signature.rawValue)
    }

    @Test func yubiKitTransportExchangesRawAPDUs() async throws {
        let recorder = RecordingYubiKitConnection()
        let transport = YubiKitYubiKeyAPDUTransport(
            exchangeData: { data in
                await recorder.record(data)
                return Data([0xCA, 0xFE, 0x90, 0x00])
            },
            closeConnection: { error in
                await recorder.close(error: error)
            }
        )

        let response = try await transport.exchange(YubiKeyPIV.selectCommand())
        await transport.close()

        #expect(response == YubiKeyAPDUResponse(data: Data([0xCA, 0xFE]), status: YubiKeyPIV.statusOK))
        #expect(await recorder.requests == [YubiKeyPIV.selectCommand().encoded])
        #expect(await recorder.closeCount == 1)
        #expect(await recorder.closeError == nil)
    }

    @Test func describesPIVRegistrationFailures() {
        #expect(
            YubiKeyPIVRegistrationError.unsupportedPublicKey(slot: .signature).errorDescription
                == "The PIV signature slot (9C) contains a key, but it is not an Ed25519 signing key."
        )
        #expect(
            YubiKeyPIVRegistrationError.noEd25519PublicKey(slot: .signature).errorDescription
                == "No Ed25519 public key was found in the PIV signature slot (9C)."
        )
        #expect(YubiKeyPIVSlot.signature.displayName == "PIV signature slot (9C)")
    }

    private static func signatureResponse(_ signature: Data) -> Data {
        var response = Data([0x7C])
        response.appendDERLength(signature.count + 2)
        response.append(0x82)
        response.appendDERLength(signature.count)
        response.append(signature)
        return response
    }
}

private actor RecordingYubiKitConnection {
    private(set) var requests: [Data] = []
    private(set) var closeCount = 0
    private(set) var closeError: String?

    func record(_ data: Data) {
        requests.append(data)
    }

    func close(error: Error?) {
        closeCount += 1
        closeError = error.map { String(describing: $0) }
    }
}

private actor RecordingYubiKeyTransport: YubiKeyAPDUTransport {
    private var responses: [YubiKeyAPDUResponse]
    private var commands: [YubiKeyAPDUCommand] = []

    var recordedCommands: [YubiKeyAPDUCommand] {
        commands
    }

    init(responses: [YubiKeyAPDUResponse]) {
        self.responses = responses
    }

    func exchange(_ command: YubiKeyAPDUCommand) throws -> YubiKeyAPDUResponse {
        commands.append(command)
        return responses.removeFirst()
    }
}

private extension Data {
    mutating func appendDERLength(_ length: Int) {
        if length < 0x80 {
            append(UInt8(length))
        } else if length <= Int(UInt8.max) {
            append(0x81)
            append(UInt8(length))
        } else {
            append(0x82)
            append(UInt8((length >> 8) & 0xFF))
            append(UInt8(length & 0xFF))
        }
    }
}
