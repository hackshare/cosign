import Foundation
import Indexer
import Squads

struct ProposalCreationSigningRequest: Identifiable {
    let id = UUID()
    let draft: TransferProposalDraft
    let signer: ProposalActionSigner
    let vault: SquadVaultRef
    let assetTitle: String
    let amountText: String
    let tokenDetails: ProposalCreationTokenDetails?
}

struct ProposalCreationTokenDetails {
    let programLabel: String
    let mint: String
    let sourceTokenAccount: String
    let destinationTokenAccount: String
    let baseUnits: UInt64
}

struct ProposalCreationResult: Identifiable {
    let id: String
    let submission: ProposalCreationSubmission
    let explorerURL: URL?

    init(submission: ProposalCreationSubmission, explorerURL: URL?) {
        id = submission.signature
        self.submission = submission
        self.explorerURL = explorerURL
    }
}

enum ProposalCreationCompletion: Equatable {
    case popBuilder
    case openProposal(UInt64)
    case inspectTransaction(String)
}

extension ProposalCreationSigningRequest {
    var reviewAction: RelayInspectionAction {
        switch draft {
        case let .sol(draft):
            return RelayInspectionAction(
                classification: "sol_transfer",
                summary: CosignCopy.ProposalCreation.transferSummary(amount: amountText),
                confidence: "high",
                effects: [
                    RelayInspectionEffect(
                        kind: "sol_transfer",
                        summary: CosignCopy.ProposalCreation.transferSummary(amount: amountText),
                        program: CosignCopy.ProposalCreation.systemProgramTitle,
                        asset: CosignCopy.ProposalCreation.solAssetSymbol,
                        amount: amountText,
                        source: vault.address,
                        destination: draft.recipient
                    )
                ],
                warnings: []
            )
        case let .token(draft):
            let transferSummary = CosignCopy.ProposalCreation.transferSummary(amount: amountText)
            var effects = [RelayInspectionEffect]()
            if let tokenDetails {
                effects.append(RelayInspectionEffect(
                    kind: "associated_token_account_create",
                    summary: CosignCopy.ProposalCreation.createRecipientTokenAccountSummary(),
                    program: CosignCopy.ProposalCreation.associatedTokenAccountProgramTitle,
                    asset: tokenDetails.mint,
                    amount: nil,
                    source: vault.address,
                    destination: tokenDetails.destinationTokenAccount
                ))
            }
            effects.append(RelayInspectionEffect(
                kind: "token_transfer",
                summary: transferSummary,
                program: tokenDetails?.relayProgramLabel ?? CosignCopy.ProposalCreation.tokenProgramTitle,
                asset: draft.mint,
                amount: amountText,
                source: tokenDetails?.sourceTokenAccount,
                destination: tokenDetails?.destinationTokenAccount
            ))
            return RelayInspectionAction(
                classification: "token_transfer",
                summary: CosignCopy.ProposalCreation.tokenTransferSummary(
                    amount: amountText,
                    createsRecipientAccount: tokenDetails != nil
                ),
                confidence: "high",
                effects: effects,
                warnings: []
            )
        }
    }

    var actionLabel: String {
        switch draft {
        case .sol:
            CosignCopy.ProposalCreation.createTransferLabel(isTokenTransfer: false)
        case .token:
            CosignCopy.ProposalCreation.createTransferLabel(isTokenTransfer: true)
        }
    }

    var recipient: String {
        switch draft {
        case let .sol(draft):
            draft.recipient
        case let .token(draft):
            draft.recipientOwner
        }
    }

    var recipientTitle: String {
        switch draft {
        case .sol:
            CosignCopy.ProposalCreation.recipientTitle
        case .token:
            CosignCopy.ProposalCreation.recipientOwnerTitle
        }
    }

    var memo: String? {
        switch draft {
        case let .sol(draft):
            draft.memo
        case let .token(draft):
            draft.memo
        }
    }
}

private extension ProposalCreationTokenDetails {
    var relayProgramLabel: String {
        switch programLabel {
        case "SPL":
            CosignCopy.ProposalCreation.splTokenProgramTitle
        case "Token-2022":
            CosignCopy.ProposalCreation.token2022ProgramTitle
        default:
            programLabel
        }
    }
}
