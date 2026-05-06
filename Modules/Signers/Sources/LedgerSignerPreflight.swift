import Core
import Foundation

public enum LedgerSignerPreflight {
    @discardableResult
    public static func verifySolanaAppAndAddress(
        expectedPubkey: Pubkey,
        transport: any LedgerAPDUTransport,
        displayAddressOnDevice: Bool = false
    ) async throws -> LedgerSolanaAppConfiguration {
        let configurationResponse = try await transport.exchange(LedgerSolanaAPDU.appConfigurationCommand())
        let configuration = try LedgerSolanaAPDU.parseAppConfiguration(configurationResponse.successfulData())

        let addressResponse = try await transport.exchange(
            LedgerSolanaAPDU.addressCommand(displayOnDevice: displayAddressOnDevice)
        )
        let actualPubkey = try LedgerSolanaAPDU.parseAddress(addressResponse.successfulData())

        guard actualPubkey == expectedPubkey else {
            throw LedgerSignerError.addressMismatch(expected: expectedPubkey, actual: actualPubkey)
        }

        return configuration
    }
}
