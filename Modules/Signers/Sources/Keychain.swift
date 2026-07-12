import Foundation
import LocalAuthentication
import Security

enum Keychain {
    static func storePrivateKey(_ keyBytes: Data, label: String) throws -> String {
        let account = "cosign.signer.\(UUID().uuidString)"

        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            [.biometryCurrentSet],
            &error
        ) else {
            if let cfError = error?.takeRetainedValue() {
                throw cfError as Error
            }
            throw KeychainError.osStatus(errSecParam)
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: label,
            kSecAttrAccessControl as String: access,
            kSecValueData as String: keyBytes,
            kSecUseDataProtectionKeychain as String: true
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.osStatus(status)
        }
        return account
    }

    static func storeMnemonic(_ mnemonic: String, forAccount account: String) throws {
        let mnemonicAccount = "\(account).mnemonic"

        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            [.biometryCurrentSet],
            &error
        ) else {
            if let cfError = error?.takeRetainedValue() {
                throw cfError as Error
            }
            throw KeychainError.osStatus(errSecParam)
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: mnemonicAccount,
            kSecAttrAccessControl as String: access,
            kSecValueData as String: Data(mnemonic.utf8),
            kSecUseDataProtectionKeychain as String: true
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            try deleteItem(account: mnemonicAccount)
            let retry = SecItemAdd(query as CFDictionary, nil)
            guard retry == errSecSuccess else {
                throw KeychainError.osStatus(retry)
            }
            return
        }
        guard status == errSecSuccess else {
            throw KeychainError.osStatus(status)
        }
    }

    static func loadMnemonic(forAccount account: String, prompt: String) throws -> String {
        let context = LAContext()
        context.localizedReason = prompt

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "\(account).mnemonic",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.osStatus(status)
        }
        guard let mnemonic = String(data: data, encoding: .utf8) else {
            throw KeychainError.osStatus(errSecDecode)
        }
        return mnemonic
    }

    /// Reads the signing key. This triggers Face ID (the item is stored behind a
    /// biometric ACL) and blocks the calling thread until the prompt resolves, so
    /// it MUST run off the main thread and only from a user-initiated action
    /// (signing, revealing a secret). Never call it at launch or inside a SwiftUI
    /// view body: a synchronous biometric read during scene-create can exhaust the
    /// launch watchdog and kill the app. For presence checks, use
    /// `privateKeyExists(account:)`, which never prompts.
    static func loadPrivateKey(account: String, prompt: String) throws -> Data {
        let context = LAContext()
        context.localizedReason = prompt

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.osStatus(status)
        }
        return data
    }

    /// Whether a private key exists for `account`, WITHOUT reading its data or
    /// evaluating the biometric ACL, so it never prompts Face ID. Safe to call at
    /// launch or inside a view body. Use this for presence checks; reading the key
    /// itself (`loadPrivateKey`) must stay on user-initiated actions.
    static func privateKeyExists(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: false,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    static func deletePrivateKey(account: String) throws {
        try deleteItem(account: account)
        try deleteItem(account: "\(account).mnemonic")
    }

    private static func deleteItem(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.osStatus(status)
        }
    }
}

enum KeychainError: Error {
    case osStatus(OSStatus)
}
