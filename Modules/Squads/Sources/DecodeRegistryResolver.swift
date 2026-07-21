import Indexer

public struct DecodeRegistryResolver: Sendable {
    private let relay: any RelayClient
    private let publicKeys: [String: String]

    public init(relay: any RelayClient, publicKeys: [String: String] = DecodeRegistryPublicKeys.all) {
        self.relay = relay
        self.publicKeys = publicKeys
    }

    public func resolve() async -> [String: [DecodeSpec]] {
        guard
            let response = try? await relay.decodeRegistry(),
            let bundle = try? DecodeRegistryVerifier.verify(response, publicKeys: publicKeys)
        else {
            return [:]
        }

        var index = [String: [DecodeSpec]]()
        for spec in bundle.specs {
            index[spec.program, default: []].append(spec)
        }
        return index
    }
}
