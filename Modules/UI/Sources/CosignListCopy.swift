import Foundation

extension CosignCopy {
    enum Activity {
        static let historySection = String(localized: "Squad history", bundle: .module)
        static let screenTitle = String(localized: "Activity", bundle: .module)
        static let searchPlaceholder = String(localized: "Search activity", bundle: .module)
        static let squadLabel = String(localized: "Squad", bundle: .module)
        static let unableToLoadTitle = String(localized: "Unable to Load Activity", bundle: .module)
        static let retryButton = String(localized: "Retry", bundle: .module)
        static let noMatchesTitle = String(localized: "No matching activity", bundle: .module)
        static let noMatchesMessage = String(localized: "No activity matches this filter.", bundle: .module)
        static let transactionsSection = String(localized: "Transactions", bundle: .module)
        static let loadMoreButton = String(localized: "Load More", bundle: .module)
        static let recentActivitySection = String(localized: "Recent Activity", bundle: .module)
        static let allActivityTitle = String(localized: "All Activity", bundle: .module)
        static let openInExplorer = String(localized: "Open in Explorer", bundle: .module)
        static let inspectTransaction = String(localized: "Inspect transaction", bundle: .module)
        static let filterAll = String(localized: "All", bundle: .module)
        static let filterDecoded = String(localized: "Decoded", bundle: .module)
        static let filterErrors = String(localized: "Errors", bundle: .module)
        static let executedStatus = String(localized: "Executed", bundle: .module)
        static let failedStatus = String(localized: "Failed", bundle: .module)
        static let unknownTimestamp = String(localized: "Unknown", bundle: .module)

        static func slot(_ slot: UInt64) -> String {
            String(localized: "Slot \(slot)", bundle: .module)
        }
    }

    enum ProposalList {
        static let historySection = String(localized: "Squad proposals", bundle: .module)
        static let screenTitle = String(localized: "Proposals", bundle: .module)
        static let squadLabel = String(localized: "Squad", bundle: .module)
        static let latestIndexLabel = String(localized: "Latest index", bundle: .module)
        static let loadedRangeLabel = String(localized: "Loaded range", bundle: .module)
        static let unableToLoadTitle = String(localized: "Unable to Load Proposals", bundle: .module)
        static let recentProposalsSection = String(localized: "Recent Proposals", bundle: .module)
        static let allProposalsTitle = String(localized: "All Proposals", bundle: .module)
        static let readyBadge = String(localized: "Ready", bundle: .module)

        static func loadedRange(from fromIndex: UInt64, to toIndex: UInt64) -> String {
            "\(fromIndex)-\(toIndex)"
        }

        static func voteSummary(approvals: UInt32, rejections: UInt32, cancellations: UInt32) -> String {
            var parts = [
                String(localized: "\(approvals) approve", bundle: .module),
                String(localized: "\(rejections) reject", bundle: .module)
            ]
            if cancellations > 0 {
                parts.append(String(localized: "\(cancellations) cancel", bundle: .module))
            }
            return parts.joined(separator: " · ")
        }
    }
}
