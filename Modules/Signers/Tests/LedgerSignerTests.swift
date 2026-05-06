import Core
import Foundation
import Testing
@testable import Signers

struct LedgerSignerTests {
    @Test func defaultSolanaPathSerializesForLedger() {
        #expect(LedgerDerivationPath.defaultSolana.serialized == Data([
            0x04,
            0x80, 0x00, 0x00, 0x2C,
            0x80, 0x00, 0x01, 0xF5,
            0x80, 0x00, 0x00, 0x00,
            0x80, 0x00, 0x00, 0x00
        ]))
    }

    @Test func buildsAddressAndConfigurationAPDUs() {
        let configuration = LedgerSolanaAPDU.appConfigurationCommand()
        #expect(configuration.encoded == Data([0xE0, 0x04, 0x00, 0x00, 0x00]))

        let address = LedgerSolanaAPDU.addressCommand(displayOnDevice: true)
        #expect(address.cla == 0xE0)
        #expect(address.instruction == 0x05)
        #expect(address.parameter1 == 0x01)
        #expect(address.parameter2 == 0x00)
        #expect(address.data == LedgerDerivationPath.defaultSolana.serialized)
    }

    @Test func chunksLongSolanaSignPayloads() {
        let message = Data(repeating: 0xAB, count: 600)
        let commands = LedgerSolanaAPDU.signTransactionCommands(message: message)

        #expect(commands.count == 3)
        #expect(commands.map(\.parameter2) == [0x02, 0x03, 0x01])
        #expect(commands.map(\.data.count) == [255, 255, 108])
        #expect(commands[0].data.first == 1)
    }

    @Test func parsesAppConfigurationResponse() throws {
        let configuration = try LedgerSolanaAPDU.parseAppConfiguration(Data([1, 0, 1, 2, 3]))

        #expect(configuration.blindSigningEnabled)
        #expect(configuration.pubkeyDisplayMode == 0)
        #expect(configuration.version == "1.2.3")
    }

    @Test func parsesAddressResponse() throws {
        let pubkey = Data(repeating: 0xAB, count: 32)

        #expect(try LedgerSolanaAPDU.parseAddress(pubkey) == pubkey)
        #expect(throws: LedgerSignerError.invalidAddressLength(31)) {
            try LedgerSolanaAPDU.parseAddress(Data(repeating: 0xAB, count: 31))
        }
    }

    @Test func ledgerPreflightVerifiesAddress() async throws {
        let pubkey = Data(repeating: 0xAB, count: 32)
        let transport = RecordingLedgerTransport(responses: [
            LedgerAPDUResponse(data: Data([1, 0, 1, 2, 3]), status: LedgerSolanaAPDU.statusOK),
            LedgerAPDUResponse(data: pubkey, status: LedgerSolanaAPDU.statusOK)
        ])

        let configuration = try await LedgerSignerPreflight.verifySolanaAppAndAddress(
            expectedPubkey: pubkey,
            transport: transport
        )
        let commands = await transport.recordedCommands

        #expect(configuration.version == "1.2.3")
        #expect(commands.map(\.instruction) == [
            LedgerSolanaAPDU.instructionGetConfiguration,
            LedgerSolanaAPDU.instructionGetAddress
        ])
        #expect(commands[1].parameter1 == LedgerSolanaAPDU.p1NonConfirm)
    }

    @Test func ledgerPreflightRejectsAddressMismatch() async throws {
        let expectedPubkey = Data(repeating: 0xAB, count: 32)
        let actualPubkey = Data(repeating: 0xCD, count: 32)
        let transport = RecordingLedgerTransport(responses: [
            LedgerAPDUResponse(data: Data([1, 0, 1, 2, 3]), status: LedgerSolanaAPDU.statusOK),
            LedgerAPDUResponse(data: actualPubkey, status: LedgerSolanaAPDU.statusOK)
        ])

        await #expect(
            throws: LedgerSignerError.addressMismatch(expected: expectedPubkey, actual: actualPubkey)
        ) {
            try await LedgerSignerPreflight.verifySolanaAppAndAddress(
                expectedPubkey: expectedPubkey,
                transport: transport
            )
        }
    }

    @Test func parsesLedgerResponses() throws {
        let response = try LedgerAPDUResponse(encoded: Data([0xAA, 0xBB, 0x90, 0x00]))

        #expect(try response.successfulData() == Data([0xAA, 0xBB]))
    }

    @Test func surfacesBlindSigningResponse() throws {
        let response = try LedgerAPDUResponse(encoded: Data([0x68, 0x08]))

        #expect(throws: LedgerSignerError.blindSigningRequired) {
            try response.successfulData()
        }
    }

    @Test func encodesAndDecodesBLEFrames() throws {
        let apdu = Data([0, 1, 2, 3, 4, 5, 6, 7])
        let frames = try LedgerBLEFraming.encodeAPDU(apdu, mtu: 8)

        #expect(frames == [
            Data([0x05, 0x00, 0x00, 0x00, 0x08, 0x00, 0x01, 0x02]),
            Data([0x05, 0x00, 0x01, 0x03, 0x04, 0x05, 0x06, 0x07])
        ])
        #expect(try LedgerBLEFraming.decodeAPDU(frames) == apdu)
    }

    @Test func exposesLedgerBLEUUIDs() {
        #expect(LedgerBLEUUID.service.uuidString == "13D63400-2C97-6004-0000-4C6564676572")
        #expect(LedgerBLEUUID.notifyCharacteristic.uuidString == "13D63400-2C97-6004-0001-4C6564676572")
        #expect(LedgerBLEUUID.writeCharacteristic.uuidString == "13D63400-2C97-6004-0002-4C6564676572")
    }

    @Test func rejectsInvalidBLEFrameSequence() throws {
        let frames = [
            Data([0x05, 0x00, 0x00, 0x00, 0x04, 0x00]),
            Data([0x05, 0x00, 0x02, 0x01, 0x02, 0x03])
        ]

        #expect(throws: LedgerBLEFramingError.invalidSequence(expected: 1, actual: 2)) {
            try LedgerBLEFraming.decodeAPDU(frames)
        }
    }

    @Test func ledgerSignerRequiresTransport() async throws {
        let signer = LedgerSigner(label: "Ledger", pubkey: Data(repeating: 1, count: 32))

        await #expect(throws: SignerError.self) {
            _ = try await signer.sign(message: Data([1, 2, 3]))
        }
    }

    @Test func ledgerSignerSubmitsChunkedSignCommands() async throws {
        let signature = Data(repeating: 0xCC, count: 64)
        let transport = RecordingLedgerTransport(responses: [
            LedgerAPDUResponse(status: LedgerSolanaAPDU.statusOK),
            LedgerAPDUResponse(data: signature, status: LedgerSolanaAPDU.statusOK)
        ])
        let signer = LedgerSigner(
            label: "Ledger",
            pubkey: Data(repeating: 1, count: 32),
            transport: transport
        )

        let submittedSignature = try await signer.sign(message: Data(repeating: 0xAB, count: 300))
        let commands = await transport.recordedCommands

        #expect(submittedSignature == signature)
        #expect(commands.count == 2)
        #expect(commands.map(\.parameter2) == [0x02, 0x01])
    }
}

private actor RecordingLedgerTransport: LedgerAPDUTransport {
    private var responses: [LedgerAPDUResponse]
    private var commands: [LedgerAPDUCommand] = []

    var recordedCommands: [LedgerAPDUCommand] {
        commands
    }

    init(responses: [LedgerAPDUResponse]) {
        self.responses = responses
    }

    func exchange(_ command: LedgerAPDUCommand) throws -> LedgerAPDUResponse {
        commands.append(command)
        return responses.removeFirst()
    }
}
