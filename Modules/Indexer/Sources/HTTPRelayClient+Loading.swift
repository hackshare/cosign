import Foundation

extension HTTPRelayClient {
    func loadJSON<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        do {
            let result = try await performLoadJSON(type, from: url)
            healthReporter?.success(.relay)
            return result
        } catch {
            healthReporter?.failure(.relay)
            throw error
        }
    }

    private func performLoadJSON<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RelayClientError.invalidResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw RelayClientError.httpStatus(
                httpResponse.statusCode,
                message: relayErrorMessage(from: data)
            )
        }

        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw RelayClientError.invalidResponse
        }
    }

    private func relayErrorMessage(from data: Data) -> String? {
        guard let error = try? decoder.decode(RelayErrorResponse.self, from: data) else {
            return nil
        }
        return error.error.message
    }
}
