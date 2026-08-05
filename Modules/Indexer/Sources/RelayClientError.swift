import Foundation

public enum RelayClientError: LocalizedError, Equatable {
    case unavailable
    case httpStatus(Int, message: String?)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "Relay feature is unavailable for this endpoint."
        case let .httpStatus(statusCode, message):
            if let message, !message.isEmpty {
                "Relay returned HTTP \(statusCode): \(message)"
            } else {
                "Relay returned HTTP \(statusCode)."
            }
        case .invalidResponse:
            "Relay did not return a valid response."
        }
    }
}

struct RelayErrorResponse: Decodable {
    let error: RelayErrorBody
}

struct RelayErrorBody: Decodable {
    let message: String
}
