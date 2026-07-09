import Core

extension SignerType {
    var displayName: String {
        switch self {
        case .hotWallet:
            "Hot wallet"
        }
    }
}
