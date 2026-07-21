import Foundation

extension HTTPRelayClient {
    func programIDLURL(for request: ProgramIDLRequest) -> URL? {
        guard supports(.programIDL) else {
            return nil
        }

        return relayURL(pathComponents: [
            "cosign",
            "v1",
            "programs",
            request.programID,
            "idl"
        ])
    }

    func programIDL(for request: ProgramIDLRequest) async throws -> ProgramIDLResponse {
        guard let url = programIDLURL(for: request) else {
            throw RelayClientError.unavailable
        }

        return try await loadJSON(ProgramIDLResponse.self, from: url)
    }
}
