public enum Network: String, Codable, Sendable, CaseIterable {
    case mainnet
    case devnet

    public var displayName: String {
        switch self {
        case .mainnet: "Mainnet"
        case .devnet: "Devnet"
        }
    }

    public var isMainnet: Bool {
        self == .mainnet
    }
}
