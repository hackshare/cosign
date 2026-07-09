import Foundation
import Indexer

extension CosignCopy {
    enum NetworkHealth {
        static let retry = String(localized: "Retry", bundle: .module)
        static let bannerAccessibilityIdentifier = "network-health-banner"

        static func updatedAgo(_ date: Date) -> String {
            let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
            return minutes < 1
                ? String(localized: "Updated just now", bundle: .module)
                : String(localized: "Updated \(minutes)m ago", bundle: .module)
        }

        static func title(for status: NetworkHealthStatus) -> String {
            switch status {
            case .webSocketDown:
                String(localized: "Live updates paused", bundle: .module)
            case .offline:
                String(localized: "Can't reach the network", bundle: .module)
            case .healthy:
                ""
            }
        }

        static func detail(for status: NetworkHealthStatus) -> String {
            switch status {
            case .webSocketDown:
                String(localized: "Reconnecting — refreshing on a timer.", bundle: .module)
            case .offline:
                String(localized: "Showing saved data.", bundle: .module)
            case .healthy:
                ""
            }
        }
    }
}
