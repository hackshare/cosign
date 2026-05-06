import Foundation
import Security

struct SecureNetworkURLKeychain {
    let load: () throws -> String?
    let save: (String) throws -> Void
    let delete: () throws -> Void

    static let rpcURL = live(account: "cosign.network.rpc-url")

    static func live(account: String) -> SecureNetworkURLKeychain {
        SecureNetworkURLKeychain(
            load: {
                let query: [String: Any] = lookupQuery(account: account).merging([
                    kSecReturnData as String: true,
                    kSecMatchLimit as String: kSecMatchLimitOne
                ]) { _, new in new }

                var item: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &item)
                if status == errSecItemNotFound {
                    return nil
                }
                guard status == errSecSuccess, let data = item as? Data else {
                    throw NetworkSettingsError.keychainFailure(status)
                }
                return String(data: data, encoding: .utf8)
            },
            save: { urlString in
                let data = Data(urlString.utf8)
                let lookupQuery = lookupQuery(account: account)
                let updateAttributes: [String: Any] = [
                    kSecValueData as String: data
                ]

                let updateStatus = SecItemUpdate(lookupQuery as CFDictionary, updateAttributes as CFDictionary)
                if updateStatus == errSecSuccess {
                    return
                }
                guard updateStatus == errSecItemNotFound else {
                    throw NetworkSettingsError.keychainFailure(updateStatus)
                }

                let addQuery = lookupQuery.merging([
                    kSecValueData as String: data,
                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                ]) { _, new in new }
                let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
                guard addStatus == errSecSuccess else {
                    throw NetworkSettingsError.keychainFailure(addStatus)
                }
            },
            delete: {
                let status = SecItemDelete(lookupQuery(account: account) as CFDictionary)
                guard status == errSecSuccess || status == errSecItemNotFound else {
                    throw NetworkSettingsError.keychainFailure(status)
                }
            }
        )
    }

    private static func lookupQuery(account: String) -> [String: Any] {
        baseQuery(account: account).merging([
            kSecUseDataProtectionKeychain as String: true
        ]) { _, new in new }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.hackshare.cosign.network",
            kSecAttrAccount as String: account
        ]
    }
}
