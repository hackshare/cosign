import Foundation

public typealias Pubkey = Data
public typealias SolanaSignature = Data

public enum SignerType: String, Codable, Sendable {
    case hotWallet
    case ledger
    case yubikey
}

public protocol Signer: Sendable {
    var label: String { get }
    var pubkey: Pubkey { get }
    var type: SignerType { get }

    func sign(message: Data) async throws -> SolanaSignature
}

public enum SignerError: Error {
    case keychainFailure(OSStatus)
    case deviceUnavailable
    case underlying(Error)
}
