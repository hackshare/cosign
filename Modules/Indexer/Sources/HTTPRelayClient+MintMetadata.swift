import Foundation

extension HTTPRelayClient {
    func mintMetadataURL(for request: MintMetadataRequest) -> URL? {
        guard supports(.mintMetadata) else {
            return nil
        }

        return relayURL(pathComponents: [
            "cosign",
            "v1",
            "mints",
            request.account
        ])
    }

    func mintMetadata(for request: MintMetadataRequest) async throws -> MintMetadataResponse {
        guard let url = mintMetadataURL(for: request) else {
            throw RelayClientError.unavailable
        }

        return try await loadJSON(MintMetadataResponse.self, from: url)
    }
}
