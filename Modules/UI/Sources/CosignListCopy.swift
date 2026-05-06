extension CosignCopy {
    enum Activity {
        static let historySection = "Squad history"
        static let screenTitle = "Activity"
        static let searchPlaceholder = "Search activity"
        static let squadLabel = "Squad"
        static let unableToLoadTitle = "Unable to Load Activity"
        static let retryButton = "Retry"
        static let noMatchesTitle = "No matching activity"
        static let noMatchesMessage = "No activity matches this filter."
        static let transactionsSection = "Transactions"
        static let loadMoreButton = "Load More"
        static let recentActivitySection = "Recent Activity"
        static let allActivityTitle = "All Activity"
        static let openInExplorer = "Open in Explorer"
        static let inspectTransaction = "Inspect transaction"
        static let filterAll = "All"
        static let filterDecoded = "Decoded"
        static let filterErrors = "Errors"
        static let executedStatus = "Executed"
        static let failedStatus = "Failed"
        static let unknownTimestamp = "Unknown"

        static func slot(_ slot: UInt64) -> String {
            "Slot \(slot)"
        }
    }

    enum ProposalList {
        static let historySection = "Squad proposals"
        static let screenTitle = "Proposals"
        static let squadLabel = "Squad"
        static let latestIndexLabel = "Latest index"
        static let loadedRangeLabel = "Loaded range"
        static let unableToLoadTitle = "Unable to Load Proposals"
        static let recentProposalsSection = "Recent Proposals"
        static let allProposalsTitle = "All Proposals"
        static let readyBadge = "Ready"

        static func loadedRange(from fromIndex: UInt64, to toIndex: UInt64) -> String {
            "\(fromIndex)-\(toIndex)"
        }

        static func voteSummary(approvals: UInt32, rejections: UInt32, cancellations: UInt32) -> String {
            var parts = [
                "\(approvals) approve",
                "\(rejections) reject"
            ]
            if cancellations > 0 {
                parts.append("\(cancellations) cancel")
            }
            return parts.joined(separator: " · ")
        }
    }
}
