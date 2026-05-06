import Foundation

public enum SolanaWebSocketAccountWatcher {
    public static func notifications(
        webSocketURL: URL,
        accounts: [String],
        commitment: String = "confirmed",
        session: URLSession = .shared,
        healthReporter: NetworkHealthReporter? = nil
    ) -> AsyncStream<Void> {
        let accounts = normalizedAccounts(accounts)
        return AsyncStream { continuation in
            guard !accounts.isEmpty else {
                continuation.finish()
                return
            }

            let task = session.webSocketTask(with: webSocketURL)
            let worker = Task {
                do {
                    task.resume()
                    try await subscribe(to: accounts, commitment: commitment, task: task)
                    healthReporter?.success(.webSocket)
                    while !Task.isCancelled {
                        _ = try await task.receive()
                        healthReporter?.success(.webSocket)
                        continuation.yield()
                    }
                } catch {
                    if !Task.isCancelled {
                        healthReporter?.failure(.webSocket)
                    }
                    continuation.finish()
                }
            }
            let pinger = Task {
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(30))
                    } catch {
                        return
                    }
                    task.sendPing { _ in }
                }
            }

            continuation.onTermination = { _ in
                worker.cancel()
                pinger.cancel()
                task.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    private static func subscribe(
        to accounts: [String],
        commitment: String,
        task: URLSessionWebSocketTask
    ) async throws {
        for (index, account) in accounts.enumerated() {
            let request: [String: Any] = [
                "jsonrpc": "2.0",
                "id": index + 1,
                "method": "accountSubscribe",
                "params": [
                    account,
                    [
                        "encoding": "base64",
                        "commitment": commitment
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: request)
            guard let message = String(data: data, encoding: .utf8) else {
                continue
            }
            try await task.send(.string(message))
        }
    }

    private static func normalizedAccounts(_ accounts: [String]) -> [String] {
        Array(Set(accounts.filter { !$0.isEmpty })).sorted()
    }
}
