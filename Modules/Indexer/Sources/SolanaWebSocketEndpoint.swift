import Foundation

enum SolanaWebSocketEndpoint {
    /// The relay's own WebSocket endpoint (its `/ws` proxy): the relay URL with
    /// an `ws(s)` scheme and a `/ws` path. The app connects here for live
    /// updates; the relay forwards to the upstream Solana WebSocket.
    static func relayWebSocketURL(for relayURL: URL) -> URL? {
        guard var components = URLComponents(url: relayURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        switch components.scheme?.lowercased() {
        case "https":
            components.scheme = "wss"
        case "http":
            components.scheme = "ws"
        case "wss", "ws":
            break
        default:
            return nil
        }
        let trimmed = components.path.hasSuffix("/")
            ? String(components.path.dropLast())
            : components.path
        components.path = trimmed + "/ws"
        return components.url
    }
}
