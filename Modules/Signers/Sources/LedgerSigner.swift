import Core
import Foundation

public protocol LedgerAPDUTransport: Sendable {
    func exchange(_ command: LedgerAPDUCommand) async throws -> LedgerAPDUResponse
}

public struct LedgerSigner: Signer {
    public let label: String
    public let pubkey: Pubkey
    public let type: SignerType = .ledger
    public let derivationPath: LedgerDerivationPath

    private let transport: (any LedgerAPDUTransport)?

    public init(
        label: String,
        pubkey: Pubkey,
        derivationPath: LedgerDerivationPath = .defaultSolana,
        transport: (any LedgerAPDUTransport)? = nil
    ) {
        self.label = label
        self.pubkey = pubkey
        self.derivationPath = derivationPath
        self.transport = transport
    }

    public func sign(message: Data) async throws -> SolanaSignature {
        guard let transport else {
            throw SignerError.deviceUnavailable
        }

        let commands = LedgerSolanaAPDU.signTransactionCommands(
            path: derivationPath,
            message: message
        )
        var signature = Data()

        for (index, command) in commands.enumerated() {
            let response = try await transport.exchange(command)
            let data = try response.successfulData()
            if index == commands.indices.last {
                signature = data
            }
        }

        guard signature.count == 64 else {
            throw SignerError.underlying(LedgerSignerError.invalidSignatureLength(signature.count))
        }

        return signature
    }
}
