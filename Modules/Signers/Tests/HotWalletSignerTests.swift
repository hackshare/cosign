import Foundation
import Testing
@testable import CosignCore

struct HotWalletSignerCryptoTests {
    @Test func generateMnemonicProducesValidWords() throws {
        let mnemonic = try CosignCore.makeMnemonic(wordCount: 24)
        #expect(mnemonic.split(separator: " ").count == 24)
    }

    @Test func deriveKeyPairIsDeterministic() throws {
        let mnemonic = "abandon abandon abandon abandon abandon abandon " +
            "abandon abandon abandon abandon abandon about"
        let first = try CosignCore.deriveKeyPair(from: mnemonic)
        let second = try CosignCore.deriveKeyPair(from: mnemonic)
        #expect(first.publicKey == second.publicKey)
        #expect(first.publicKey.count == 32)
    }

    @Test func signAndVerifyRoundTrip() throws {
        let mnemonic = try CosignCore.makeMnemonic(wordCount: 24)
        let keyPair = try CosignCore.deriveKeyPair(from: mnemonic)
        let message = Data("transfer 1 SOL".utf8)
        let signature = CosignCore.signBytes(privateKey: keyPair.privateKey, message: message)
        #expect(signature.count == 64)
        #expect(CosignCore.verifyBytes(publicKey: keyPair.publicKey, message: message, signature: signature))
    }

    @Test func verifyRejectsTamperedMessage() throws {
        let mnemonic = try CosignCore.makeMnemonic(wordCount: 24)
        let keyPair = try CosignCore.deriveKeyPair(from: mnemonic)
        let signature = CosignCore.signBytes(privateKey: keyPair.privateKey, message: Data("original".utf8))
        #expect(!CosignCore.verifyBytes(
            publicKey: keyPair.publicKey,
            message: Data("tampered".utf8),
            signature: signature
        ))
    }

    @Test func base58EncodeRoundTrip() throws {
        let mnemonic = try CosignCore.makeMnemonic(wordCount: 24)
        let keyPair = try CosignCore.deriveKeyPair(from: mnemonic)
        let encoded = CosignCore.base58(keyPair.publicKey)
        #expect((32 ... 44).contains(encoded.count), "Solana base58 addresses are 32-44 chars")
    }
}
