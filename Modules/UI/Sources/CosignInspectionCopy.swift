import Foundation

extension CosignCopy {
    enum ActionObject {
        static let reviewRawInstructionsBeforeSigningTitle = String(
            localized: "Review raw instructions before signing.",
            bundle: .module
        )
        static let reviewUnknownExecutedInstructionsTitle = String(
            localized: "Review unknown executed instructions.",
            bundle: .module
        )
        static let manualReviewRequiredSubtitle = String(localized: "Manual review required", bundle: .module)
        static let routineSeverity = String(localized: "Routine", bundle: .module)
        static let authoritySeverity = String(localized: "Authority change", bundle: .module)
        static let highRiskSeverity = String(localized: "High-risk", bundle: .module)
        static let decodedConfidence = String(localized: "Decoded", bundle: .module)
        static let idlConfidence = String(localized: "IDL", bundle: .module)
        static let partialConfidence = String(localized: "Partial", bundle: .module)
        static let unknownConfidence = String(localized: "Unknown", bundle: .module)
        static let amountRole = String(localized: "Amount", bundle: .module)
        static let assetRole = String(localized: "Asset", bundle: .module)
        static let fromRole = String(localized: "From", bundle: .module)
        static let toRole = String(localized: "To", bundle: .module)
        static let programRole = String(localized: "Program", bundle: .module)
        static let actionRole = String(localized: "Action", bundle: .module)
    }
}

extension CosignCopy {
    enum TransactionInspection {
        static let navigationTitle = String(localized: "Transaction", bundle: .module)
        static let relayInspectionTitle = String(localized: "Relay inspection", bundle: .module)
        static let executedTransactionTitle = String(localized: "Executed transaction", bundle: .module)
        static let transactionTitle = String(localized: "Transaction", bundle: .module)
        static let signatureTitle = String(localized: "Signature", bundle: .module)
        static let copySignatureAccessibilityLabel = String(localized: "Copy Transaction Signature", bundle: .module)
        static let openInExplorerTitle = String(localized: "Open in Explorer", bundle: .module)
        static let inspectionSectionTitle = String(localized: "Inspection", bundle: .module)
        static let unableToInspectTitle = String(localized: "Unable to Inspect Transaction", bundle: .module)
        static let retryButton = String(localized: "Retry", bundle: .module)
        static let executionTitle = String(localized: "Execution", bundle: .module)
        static let slotLabel = String(localized: "Slot", bundle: .module)
        static let executionLogsTitle = String(localized: "Execution logs", bundle: .module)

        static func logCount(_ count: Int) -> String {
            String(localized: "\(count) log\(count == 1 ? "" : "s")", bundle: .module)
        }
    }
}

extension CosignCopy.ProposalDetail {
    static let simulationTitle = String(localized: "Simulation", bundle: .module)
    static let feePayerTitle = String(localized: "Fee payer", bundle: .module)
    static let recentBlockhashTitle = String(localized: "Recent blockhash", bundle: .module)
    static let simulationLogsTitle = String(localized: "Simulation logs", bundle: .module)
    static let noInstructionsMessage = String(
        localized: "No instructions returned by relay inspection.",
        bundle: .module
    )
    static let instructionDetailsTitle = String(localized: "Instruction details", bundle: .module)
    static let linksSectionTitle = String(localized: "Links", bundle: .module)
    static let simulateTransactionTitle = String(localized: "Simulate Transaction", bundle: .module)
    static let refreshingInspectionTitle = String(localized: "Refreshing Inspection", bundle: .module)
    static let refreshInspectionTitle = String(localized: "Refresh Inspection", bundle: .module)
    static let refreshInspectionAndSimulationTitle = String(
        localized: "Refresh Inspection and Simulation",
        bundle: .module
    )
    static let openExecutedTransactionTitle = String(localized: "Open Executed Transaction", bundle: .module)
    static let openTransactionAccountTitle = String(localized: "Open Transaction Account", bundle: .module)

    static func instructionCount(_ count: Int) -> String {
        String(localized: "\(count) instruction\(count == 1 ? "" : "s")", bundle: .module)
    }

    static func instructionFallbackTitle(count: Int) -> String {
        switch count {
        case 0:
            String(localized: "No Instructions", bundle: .module)
        case 1:
            ""
        default:
            String(localized: "\(count) Instructions", bundle: .module)
        }
    }
}
