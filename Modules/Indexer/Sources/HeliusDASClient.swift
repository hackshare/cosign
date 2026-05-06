import Foundation

enum HeliusDASClientError: Error, Equatable {
    case invalidResponse
    case rpcError(code: Int, message: String)
}

public final class HeliusDASClient: @unchecked Sendable {
    public static let tokenProgramID = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
    public static let token2022ProgramID = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"

    private let rpcURL: URL
    private let session: URLSession
    private let healthReporter: NetworkHealthReporter?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        rpcURL: URL,
        session: URLSession = .shared,
        healthReporter: NetworkHealthReporter? = nil
    ) {
        self.rpcURL = rpcURL
        self.session = session
        self.healthReporter = healthReporter
    }

    public func getAssetsByOwner(owner: String) async throws -> [DASAsset] {
        do {
            let assets = try await getDASAssetsByOwner(owner: owner)
            return try await assetsWithTokenProgramMetadata(assets, owner: owner)
        } catch let error as HeliusDASClientError where error.isMethodNotFound {
            return try await getFungibleTokenAccountsByOwner(owner: owner)
        }
    }

    public func getNativeBalance(pubkey: String) async throws -> UInt64 {
        let request = RPCRequest(method: "getBalance", params: [.string(pubkey)])
        let response: NativeBalanceResponse = try await send(request)
        return response.value
    }

    /// The on-chain `owner` program of an account, or nil if the account does
    /// not exist yet (a fresh wallet address).
    public func getAccountOwner(pubkey: String) async throws -> String? {
        let request = RPCRequest(
            method: "getAccountInfo",
            params: [.string(pubkey), .dictionary(["encoding": .string("base64")])]
        )
        let response: AccountInfoResponse = try await send(request)
        return response.value?.owner
    }

    /// The network fee (lamports) paid by a confirmed transaction, or nil if it
    /// can't be read yet.
    public func getTransactionFee(signature: String) async throws -> UInt64? {
        let request = RPCRequest(
            method: "getTransaction",
            params: [.string(signature), .dictionary(["maxSupportedTransactionVersion": .int(0)])]
        )
        let response: TransactionResponse = try await send(request)
        return response.meta?.fee
    }

    public static func decodeAssetsByOwnerResponse(_ data: Data) throws -> [DASAsset] {
        let response: AssetsByOwnerResponse = try decodeEnvelope(data)
        return response.items.map(DASAsset.init(item:))
    }

    static func decodeTokenAccountsByOwnerResponse(_ data: Data) throws -> [DASAsset] {
        let response: TokenAccountsByOwnerResponse = try decodeEnvelope(data)
        return response.value.compactMap(DASAsset.init(tokenAccount:))
    }

    private func getDASAssetsByOwner(owner: String) async throws -> [DASAsset] {
        let request = RPCRequest(
            method: "getAssetsByOwner",
            params: [
                "ownerAddress": .string(owner),
                "page": 1,
                "limit": 1000,
                "displayOptions": [
                    "showFungible": true,
                    "showNativeBalance": false,
                    "showCollectionMetadata": false
                ]
            ]
        )
        let response: AssetsByOwnerResponse = try await send(request)
        return response.items.map(DASAsset.init(item:))
    }

    private func getFungibleTokenAccountsByOwner(owner: String) async throws -> [DASAsset] {
        var assets = [DASAsset]()
        var loadedAnyProgram = false
        var firstError: Error?

        for programID in [Self.tokenProgramID, Self.token2022ProgramID] {
            let request = RPCRequest(
                method: "getTokenAccountsByOwner",
                params: [
                    .string(owner),
                    ["programId": .string(programID)],
                    ["encoding": "jsonParsed"]
                ]
            )

            do {
                let response: TokenAccountsByOwnerResponse = try await send(request)
                loadedAnyProgram = true
                assets.append(contentsOf: response.value.compactMap(DASAsset.init(tokenAccount:)))
            } catch {
                firstError = firstError ?? error
            }
        }

        if !loadedAnyProgram, let firstError {
            throw firstError
        }

        return assets.sorted { $0.id < $1.id }
    }

    private func assetsWithTokenProgramMetadata(_ assets: [DASAsset], owner: String) async throws -> [DASAsset] {
        let tokenAccounts = await (try? getFungibleTokenAccountsByOwner(owner: owner)) ?? []
        let programByMint = Dictionary(
            tokenAccounts.compactMap { asset in
                asset.tokenProgramID.map { (asset.id, $0) }
            },
            uniquingKeysWith: { existing, _ in existing }
        )

        return assets.map { asset in
            guard
                asset.kind == .fungible,
                asset.tokenProgramID == nil,
                let tokenProgramID = programByMint[asset.id]
            else {
                return asset
            }
            return asset.withTokenProgramID(tokenProgramID)
        }
    }

    private func send<Response: Decodable>(_ rpcRequest: RPCRequest) async throws -> Response {
        do {
            let response: Response = try await performSend(rpcRequest)
            healthReporter?.success(.rpc)
            return response
        } catch {
            healthReporter?.failure(.rpc)
            throw error
        }
    }

    private func performSend<Response: Decodable>(_ rpcRequest: RPCRequest) async throws -> Response {
        let data = try encoder.encode(rpcRequest)
        var request = URLRequest(url: endpointURL())
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        var attempt = 0
        while true {
            let (responseData, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw HeliusDASClientError.invalidResponse
            }

            if http.statusCode == 429, attempt < 2 {
                attempt += 1
                let delay = UInt64(pow(2.0, Double(attempt)) * 250_000_000)
                try await Task.sleep(nanoseconds: delay)
                continue
            }

            guard (200 ..< 300).contains(http.statusCode) else {
                throw HeliusDASClientError.invalidResponse
            }

            return try Self.decodeEnvelope(responseData, decoder: decoder)
        }
    }

    private static func decodeEnvelope<Response: Decodable>(
        _ data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> Response {
        let envelope = try decoder.decode(RPCEnvelope<Response>.self, from: data)
        if let error = envelope.error {
            throw HeliusDASClientError.rpcError(code: error.code, message: error.message)
        }
        guard let result = envelope.result else {
            throw HeliusDASClientError.invalidResponse
        }
        return result
    }

    /// The relay holds the upstream RPC credentials; the app posts to the relay
    /// root and never carries an API key.
    private func endpointURL() -> URL {
        rpcURL
    }
}

private extension HeliusDASClientError {
    var isMethodNotFound: Bool {
        guard case let .rpcError(code, message) = self else {
            return false
        }
        return code == -32601 || message.localizedCaseInsensitiveContains("method not found")
    }
}

private struct RPCRequest: Encodable {
    let jsonrpc = "2.0"
    let id = "cosign"
    let method: String
    let params: EncodableValue
}

private struct RPCEnvelope<Result: Decodable>: Decodable {
    let result: Result?
    let error: RPCError?
}

private struct RPCError: Decodable {
    let code: Int
    let message: String
}

private struct NativeBalanceResponse: Decodable {
    let value: UInt64
}

private struct AccountInfoResponse: Decodable {
    struct Value: Decodable {
        let owner: String
    }

    let value: Value?
}

private struct TransactionResponse: Decodable {
    struct Meta: Decodable {
        let fee: UInt64?
    }

    let meta: Meta?
}

private enum EncodableValue: Encodable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case array([EncodableValue])
    case dictionary([String: EncodableValue])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .array(values):
            try container.encode(values)
        case let .dictionary(values):
            try container.encode(values)
        }
    }
}

extension EncodableValue: ExpressibleByArrayLiteral {
    init(arrayLiteral elements: EncodableValue...) {
        self = .array(elements)
    }
}

extension EncodableValue: ExpressibleByDictionaryLiteral {
    init(dictionaryLiteral elements: (String, EncodableValue)...) {
        self = .dictionary(Dictionary(uniqueKeysWithValues: elements))
    }
}

extension EncodableValue: ExpressibleByBooleanLiteral {
    init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension EncodableValue: ExpressibleByIntegerLiteral {
    init(integerLiteral value: Int) {
        self = .int(value)
    }
}

extension EncodableValue: ExpressibleByStringLiteral {
    init(stringLiteral value: String) {
        self = .string(value)
    }
}
