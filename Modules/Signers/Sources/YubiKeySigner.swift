import Core
import Foundation

public protocol YubiKeyAPDUTransport: Sendable {
    func exchange(_ command: YubiKeyAPDUCommand) async throws -> YubiKeyAPDUResponse
}

public typealias YubiKeyPINProvider = @Sendable () async throws -> String

public struct YubiKeySigner: Signer {
    public let label: String
    public let pubkey: Pubkey
    public let type: SignerType = .yubikey
    public let slot: YubiKeyPIVSlot

    private let transport: (any YubiKeyAPDUTransport)?
    private let pinProvider: YubiKeyPINProvider?

    public init(
        label: String,
        pubkey: Pubkey,
        slot: YubiKeyPIVSlot = .signature,
        transport: (any YubiKeyAPDUTransport)? = nil,
        pinProvider: YubiKeyPINProvider? = nil
    ) {
        self.label = label
        self.pubkey = pubkey
        self.slot = slot
        self.transport = transport
        self.pinProvider = pinProvider
    }

    public func sign(message: Data) async throws -> SolanaSignature {
        guard let transport else {
            throw SignerError.deviceUnavailable
        }
        guard let pinProvider else {
            throw SignerError.underlying(YubiKeySignerError.missingPINProvider)
        }

        let pin = try await pinProvider()

        _ = try await transport.exchange(YubiKeyPIV.selectCommand()).successfulData()
        _ = try await transport.exchange(YubiKeyPIV.verifyPINCommand(pin)).successfulData()

        var signatureResponseData = Data()
        let commands = YubiKeyPIV.ed25519SignCommands(message: message, slot: slot)
        for (index, command) in commands.enumerated() {
            let responseData = try await transport.exchange(command).successfulData()
            if index == commands.indices.last {
                signatureResponseData = responseData
            }
        }

        return try YubiKeyPIV.parseEd25519Signature(signatureResponseData)
    }
}
