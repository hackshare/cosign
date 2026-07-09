public struct RelayPrices: Decodable, Equatable, Sendable {
    public let prices: [String: Double]
    /// Per-mint 24h price change, as a percentage (e.g. -1.55). Absent for
    /// mints without data and for older relays that predate the field.
    public let changes: [String: Double]

    public init(prices: [String: Double], changes: [String: Double] = [:]) {
        self.prices = prices
        self.changes = changes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        prices = try container.decodeIfPresent([String: Double].self, forKey: .prices) ?? [:]
        changes = try container.decodeIfPresent([String: Double].self, forKey: .changes) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case prices
        case changes
    }
}
