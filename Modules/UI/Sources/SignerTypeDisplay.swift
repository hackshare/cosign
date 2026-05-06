import Core

extension SignerType {
    var displayName: String {
        switch self {
        case .hotWallet:
            "Hot wallet"
        case .ledger:
            "Ledger"
        case .yubikey:
            "YubiKey"
        }
    }
}
