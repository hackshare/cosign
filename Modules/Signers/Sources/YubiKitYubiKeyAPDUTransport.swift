import Foundation
import YubiKit

public enum YubiKeyConnectionPreference: Equatable, Sendable {
    case wired
    case nfc(alertMessage: String? = nil)
}

public final class YubiKitYubiKeyAPDUTransport: YubiKeyAPDUTransport, Sendable {
    private let exchangeData: @Sendable (Data) async throws -> Data
    private let closeConnection: @Sendable (Error?) async -> Void

    init(
        exchangeData: @escaping @Sendable (Data) async throws -> Data,
        closeConnection: @escaping @Sendable (Error?) async -> Void
    ) {
        self.exchangeData = exchangeData
        self.closeConnection = closeConnection
    }

    public static func open(
        _ preference: YubiKeyConnectionPreference
    ) async throws -> YubiKitYubiKeyAPDUTransport {
        switch preference {
        case .wired:
            try await wired()
        case let .nfc(alertMessage):
            try await nfc(alertMessage: alertMessage)
        }
    }

    public static func wired() async throws -> YubiKitYubiKeyAPDUTransport {
        let connection = try await WiredSmartCardConnection.makeConnection()
        return YubiKitYubiKeyAPDUTransport(
            exchangeData: { data in
                try await connection.send(data: data)
            },
            closeConnection: { error in
                await connection.close(error: error)
            }
        )
    }

    public static func nfc(
        alertMessage: String? = "Hold your YubiKey near this iPhone."
    ) async throws -> YubiKitYubiKeyAPDUTransport {
        let connection = try await NFCSmartCardConnection(alertMessage: alertMessage)
        return YubiKitYubiKeyAPDUTransport(
            exchangeData: { data in
                try await connection.send(data: data)
            },
            closeConnection: { error in
                if let error {
                    await connection.close(error: error)
                } else {
                    await connection.close(message: "YubiKey signing complete.")
                }
            }
        )
    }

    public func exchange(_ command: YubiKeyAPDUCommand) async throws -> YubiKeyAPDUResponse {
        let responseData = try await exchangeData(command.encoded)
        return try YubiKeyAPDUResponse(encoded: responseData)
    }

    public func close(error: Error? = nil) async {
        await closeConnection(error)
    }
}
