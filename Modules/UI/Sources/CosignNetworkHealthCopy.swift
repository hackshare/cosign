import Foundation
import Indexer

extension CosignCopy {
    enum NetworkHealth {
        static let retry = "Retry"
        static let bannerAccessibilityIdentifier = "network-health-banner"

        static func updatedAgo(_ date: Date) -> String {
            let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
            return minutes < 1 ? "Updated just now" : "Updated \(minutes)m ago"
        }

        static func title(for status: NetworkHealthStatus) -> String {
            switch status {
            case .webSocketDown:
                "Live updates paused"
            case .offline:
                "Can't reach the network"
            case .healthy:
                ""
            }
        }

        static func detail(for status: NetworkHealthStatus) -> String {
            switch status {
            case .webSocketDown:
                "Reconnecting — refreshing on a timer."
            case .offline:
                "Showing saved data."
            case .healthy:
                ""
            }
        }
    }
}
