extension CosignCopy {
    enum ActionObject {
        static let reviewRawInstructionsBeforeSigningTitle = "Review raw instructions before signing."
        static let reviewUnknownExecutedInstructionsTitle = "Review unknown executed instructions."
        static let manualReviewRequiredSubtitle = "Manual review required"
        static let routineSeverity = "Routine"
        static let authoritySeverity = "Authority change"
        static let highRiskSeverity = "High-risk"
        static let decodedConfidence = "Decoded"
        static let idlConfidence = "IDL"
        static let partialConfidence = "Partial"
        static let unknownConfidence = "Unknown"
        static let amountRole = "Amount"
        static let assetRole = "Asset"
        static let fromRole = "From"
        static let toRole = "To"
        static let programRole = "Program"
        static let actionRole = "Action"
    }
}

extension CosignCopy {
    enum TransactionInspection {
        static let navigationTitle = "Transaction"
        static let relayInspectionTitle = "Relay inspection"
        static let executedTransactionTitle = "Executed transaction"
        static let transactionTitle = "Transaction"
        static let signatureTitle = "Signature"
        static let copySignatureAccessibilityLabel = "Copy Transaction Signature"
        static let openInExplorerTitle = "Open in Explorer"
        static let inspectionSectionTitle = "Inspection"
        static let unableToInspectTitle = "Unable to Inspect Transaction"
        static let retryButton = "Retry"
        static let executionTitle = "Execution"
        static let slotLabel = "Slot"
        static let executionLogsTitle = "Execution logs"

        static func logCount(_ count: Int) -> String {
            "\(count) log\(count == 1 ? "" : "s")"
        }
    }
}

extension CosignCopy.ProposalDetail {
    static let simulationTitle = "Simulation"
    static let feePayerTitle = "Fee payer"
    static let recentBlockhashTitle = "Recent blockhash"
    static let simulationLogsTitle = "Simulation logs"
    static let noInstructionsMessage = "No instructions returned by relay inspection."
    static let instructionDetailsTitle = "Instruction details"
    static let linksSectionTitle = "Links"
    static let simulateTransactionTitle = "Simulate Transaction"
    static let refreshingInspectionTitle = "Refreshing Inspection"
    static let refreshInspectionTitle = "Refresh Inspection"
    static let refreshInspectionAndSimulationTitle = "Refresh Inspection and Simulation"
    static let openExecutedTransactionTitle = "Open Executed Transaction"
    static let openTransactionAccountTitle = "Open Transaction Account"

    static func instructionCount(_ count: Int) -> String {
        "\(count) instruction\(count == 1 ? "" : "s")"
    }

    static func instructionFallbackTitle(count: Int) -> String {
        switch count {
        case 0:
            "No Instructions"
        case 1:
            ""
        default:
            "\(count) Instructions"
        }
    }
}
