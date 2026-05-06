import Core
import CosignCore
import Foundation

enum HotWalletImportError: Error {
    case invalidKeyLength(Int)
}

public struct HotWalletSigner: Signer {
    public let label: String
    public let pubkey: Pubkey
    public let type: SignerType = .hotWallet
    public let keychainAccount: String

    public init(label: String, pubkey: Pubkey, keychainAccount: String) {
        self.label = label
        self.pubkey = pubkey
        self.keychainAccount = keychainAccount
    }

    public func sign(message: Data) async throws -> SolanaSignature {
        let key: Data
        do {
            key = try Keychain.loadPrivateKey(
                account: keychainAccount,
                prompt: "Sign with \(label)"
            )
        } catch let KeychainError.osStatus(status) {
            throw SignerError.keychainFailure(status)
        } catch {
            throw SignerError.underlying(error)
        }

        return CosignCore.signBytes(privateKey: key, message: message)
    }

    /// Generate a new mnemonic + Solana keypair, store the private key in the
    /// Keychain behind a biometric ACL. The returned mnemonic must be displayed
    /// to the user for backup and then discarded — it is not stored anywhere.
    public static func generate(
        label: String,
        wordCount: UInt8 = 24
    ) throws -> (signer: HotWalletSigner, mnemonic: String) {
        let mnemonic = try CosignCore.makeMnemonic(wordCount: wordCount)
        let keyPair = try CosignCore.deriveKeyPair(from: mnemonic)
        let account = try Keychain.storePrivateKey(keyPair.privateKey, label: label)
        try Keychain.storeMnemonic(mnemonic, forAccount: account)
        return (
            HotWalletSigner(
                label: label,
                pubkey: keyPair.publicKey,
                keychainAccount: account
            ),
            mnemonic
        )
    }

    /// Restore a hot wallet from an existing mnemonic.
    public static func restore(label: String, mnemonic: String) throws -> HotWalletSigner {
        let keyPair = try CosignCore.deriveKeyPair(from: mnemonic)
        let account = try Keychain.storePrivateKey(keyPair.privateKey, label: label)
        try Keychain.storeMnemonic(mnemonic, forAccount: account)
        return HotWalletSigner(
            label: label,
            pubkey: keyPair.publicKey,
            keychainAccount: account
        )
    }

    /// Load this hot wallet's recovery phrase from the Keychain behind the
    /// biometric ACL. Throws if no mnemonic is stored (e.g. signers seeded from
    /// a raw keypair via `importKeypair`). `prompt` is the biometric reason and
    /// must be supplied by the UI layer so user-facing copy stays centralized.
    public func revealMnemonic(prompt: String) throws -> String {
        do {
            return try Keychain.loadMnemonic(forAccount: keychainAccount, prompt: prompt)
        } catch let KeychainError.osStatus(status) {
            throw SignerError.keychainFailure(status)
        } catch {
            throw SignerError.underlying(error)
        }
    }

    /// Import an existing 64-byte Solana keypair (32-byte seed followed by the
    /// 32-byte public key) — used to seed devnet test fixtures. The seed is
    /// stored in the Keychain; the public key is taken from the trailing bytes.
    public static func importKeypair(label: String, keypair64: Data) throws -> HotWalletSigner {
        guard keypair64.count == 64 else {
            throw HotWalletImportError.invalidKeyLength(keypair64.count)
        }
        let seed = Data(keypair64.prefix(32))
        let pubkey = Data(keypair64.suffix(32))
        let account = try Keychain.storePrivateKey(seed, label: label)
        return HotWalletSigner(label: label, pubkey: pubkey, keychainAccount: account)
    }

    /// Permanently delete this signer's private key from the Keychain.
    public func eraseFromKeychain() throws {
        try Keychain.deletePrivateKey(account: keychainAccount)
    }

    /// Permanently delete a hot-wallet private key by its Keychain account
    /// reference. Used when removing a signer from persistence — we don't
    /// have a `HotWalletSigner` instance handy at that point, only the
    /// stored account string.
    public static func eraseFromKeychain(account: String) throws {
        try Keychain.deletePrivateKey(account: account)
    }
}
