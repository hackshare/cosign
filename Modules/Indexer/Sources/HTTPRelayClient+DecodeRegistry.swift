import Foundation

extension HTTPRelayClient {
    func decodeRegistryURL() -> URL? {
        guard supports(.decodeRegistry) else {
            return nil
        }
        return relayURL(pathComponents: ["cosign", "v1", "decode-registry"])
    }

    func decodeRegistry() async throws -> DecodeRegistryResponse {
        guard let url = decodeRegistryURL() else {
            throw RelayClientError.unavailable
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw RelayClientError.invalidResponse
            }
            guard (200 ..< 300).contains(httpResponse.statusCode) else {
                throw RelayClientError.httpStatus(httpResponse.statusCode, message: nil)
            }
            let signature = httpResponse.value(forHTTPHeaderField: "X-Cosign-Registry-Signature") ?? ""
            healthReporter?.success(.relay)
            return DecodeRegistryResponse(bundleData: data, signatureBase64: signature)
        } catch {
            healthReporter?.failure(.relay)
            throw error
        }
    }
}
