import Foundation

public struct SOLTransferProposalDraft: Equatable, Sendable {
    public let vaultIndex: UInt8
    public let recipient: String
    public let lamports: UInt64
    public let memo: String?

    public init(vaultIndex: UInt8, recipient: String, lamports: UInt64, memo: String?) {
        self.vaultIndex = vaultIndex
        self.recipient = recipient
        self.lamports = lamports
        self.memo = memo
    }
}

public struct TokenTransferProposalDraft: Equatable, Sendable {
    public let vaultIndex: UInt8
    public let recipientOwner: String
    public let mint: String
    public let amount: UInt64
    public let decimals: UInt8
    public let tokenProgramID: String
    public let memo: String?

    public init(
        vaultIndex: UInt8,
        recipientOwner: String,
        mint: String,
        amount: UInt64,
        decimals: UInt8,
        tokenProgramID: String,
        memo: String?
    ) {
        self.vaultIndex = vaultIndex
        self.recipientOwner = recipientOwner
        self.mint = mint
        self.amount = amount
        self.decimals = decimals
        self.tokenProgramID = tokenProgramID
        self.memo = memo
    }
}

public enum TransferProposalDraft: Equatable, Sendable {
    case sol(SOLTransferProposalDraft)
    case token(TokenTransferProposalDraft)
}

public struct ProposalCreationSubmission: Equatable, Sendable {
    public let signature: String
    public let transactionIndex: UInt64
    public let proposalAddress: String
    public let transactionAddress: String
    public let vaultAddress: String
    public let proposal: SquadProposalDetail?

    public init(
        signature: String,
        transactionIndex: UInt64,
        proposalAddress: String,
        transactionAddress: String,
        vaultAddress: String,
        proposal: SquadProposalDetail?
    ) {
        self.signature = signature
        self.transactionIndex = transactionIndex
        self.proposalAddress = proposalAddress
        self.transactionAddress = transactionAddress
        self.vaultAddress = vaultAddress
        self.proposal = proposal
    }
}

enum ProposalCreationError: Error, Equatable {
    case invalidAmount
    case signerNotMember(String)
    case missingInitiatePermission
    case vaultNotFound(UInt8)
    case simulationFailed(String)
    case transactionFailed(String)
    case confirmationTimedOut(String)
}

extension ProposalCreationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            "Enter an amount greater than zero."
        case let .signerNotMember(address):
            """
            The selected signer is not a member of this Squad on the current RPC endpoint. \
            Check Settings if \(address) should belong to this Squad.
            """
        case .missingInitiatePermission:
            "The selected signer does not have permission to create proposals for this Squad."
        case let .vaultNotFound(index):
            "Vault \(index) is not available on this Squad."
        case let .simulationFailed(message):
            "Simulation failed: \(message)"
        case let .transactionFailed(message):
            "Transaction failed: \(message)"
        case let .confirmationTimedOut(signature):
            "Transaction submitted but was not confirmed yet: \(signature)"
        }
    }
}

public enum DisplayAmountParser {
    public static func baseUnits(from text: String, decimals: UInt8) -> UInt64? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("-") else {
            return nil
        }

        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard (1 ... 2).contains(parts.count) else {
            return nil
        }

        let wholeText = parts[0]
        guard wholeText.allSatisfy(\.isNumber) else {
            return nil
        }

        let fractionText = parts.count == 2 ? parts[1] : ""
        let decimalCount = Int(decimals)
        guard fractionText.allSatisfy(\.isNumber), fractionText.count <= decimalCount else {
            return nil
        }

        let whole = UInt64(wholeText) ?? 0
        let multiplier = baseUnitMultiplier(decimals: decimals)
        guard let multiplier else {
            return nil
        }

        let paddedFraction = fractionText + String(repeating: "0", count: decimalCount - fractionText.count)
        let fraction = UInt64(paddedFraction) ?? 0

        let wholeBaseUnits = whole.multipliedReportingOverflow(by: multiplier)
        guard !wholeBaseUnits.overflow else {
            return nil
        }

        let total = wholeBaseUnits.partialValue.addingReportingOverflow(fraction)
        return total.overflow ? nil : total.partialValue
    }

    private static func baseUnitMultiplier(decimals: UInt8) -> UInt64? {
        var multiplier: UInt64 = 1
        for _ in 0 ..< decimals {
            let next = multiplier.multipliedReportingOverflow(by: 10)
            guard !next.overflow else {
                return nil
            }
            multiplier = next.partialValue
        }
        return multiplier
    }
}
