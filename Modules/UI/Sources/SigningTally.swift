import Foundation

enum SigningTally {
    private static let defaults = UserDefaults(suiteName: "com.hackshare.cosign.signing-tally") ?? .standard

    static func increment(for address: String) {
        defaults.set(count(for: address) + 1, forKey: storageKey(for: address))
    }

    static func count(for address: String) -> Int {
        defaults.integer(forKey: storageKey(for: address))
    }

    static func set(for address: String, count: Int) {
        defaults.set(count, forKey: storageKey(for: address))
    }

    static func reset(for address: String) {
        defaults.removeObject(forKey: storageKey(for: address))
    }

    private static func storageKey(for address: String) -> String {
        "signingTally.\(address)"
    }
}
