import Foundation

extension CosignCopy.ProposalCreation {
    static let newProposalSection = String(localized: "New proposal", bundle: .module)
    static let transferTitle = String(localized: "Transfer", bundle: .module)
    static let unableToLoadSquadTitle = String(localized: "Unable to Load Squad", bundle: .module)
    static let retryButton = String(localized: "Retry", bundle: .module)
    static let createTransferNavigationTitle = String(localized: "Create Transfer", bundle: .module)
    static let selectVaultTitle = String(localized: "Select vault", bundle: .module)
    static let selectSignerTitle = String(localized: "Select signer", bundle: .module)
    static let selectAssetTitle = String(localized: "Select asset", bundle: .module)
    static let selectSignerSubtitle = String(
        localized: "Choose the local signer that creates this proposal.",
        bundle: .module
    )
    static let selectVaultSubtitle = String(
        localized: "Choose the vault that will send funds if the proposal executes.",
        bundle: .module
    )
    static let selectAssetSubtitle = String(
        localized: "Choose the asset to transfer from the selected vault.",
        bundle: .module
    )
    static let vaultAssetStepHeadline = String(localized: "What are you moving?", bundle: .module)
    static let vaultAssetStepSubtitle = String(
        localized: "Choose the source vault and asset. We'll route the rest.",
        bundle: .module
    )
    static let recipientStepHeadline = String(localized: "Where is it going?", bundle: .module)
    static let recipientStepSubtitle = String(
        localized: "Paste a Solana address, scan a QR code, or choose a known recipient.",
        bundle: .module
    )
    static let amountStepHeadline = String(localized: "How much?", bundle: .module)
    static let amountStepSubtitle = String(
        localized: "Enter the amount and an optional memo for the proposal.",
        bundle: .module
    )
    static let reviewStepHeadline = String(localized: "Review proposal", bundle: .module)
    static let reviewStepSubtitle = String(localized: "This is exactly what other signers will see.", bundle: .module)
    static let fromVaultLabel = String(localized: "From vault", bundle: .module)
    static let nextButton = String(localized: "Next", bundle: .module)
    static let backButton = String(localized: "Back", bundle: .module)
    static let pasteButton = String(localized: "Paste", bundle: .module)
    static let scanQRButton = String(localized: "Scan QR", bundle: .module)
    static let knownRecipientButton = String(localized: "Known", bundle: .module)
    static let maxAmountButton = String(localized: "Max", bundle: .module)
    static let recipientAddressPlaceholder = String(localized: "Recipient address", bundle: .module)
    static let recipientOwnerAddressPlaceholder = String(localized: "Recipient owner address", bundle: .module)
    static let clearRecipientAddressAccessibilityLabel = String(localized: "Clear Recipient Address", bundle: .module)
    static let pasteRecipientAddressAccessibilityLabel = String(localized: "Paste Recipient Address", bundle: .module)
    static let clearAmountAccessibilityLabel = String(localized: "Clear Amount", bundle: .module)
    static let optionalMemoPlaceholder = String(localized: "Optional memo", bundle: .module)
    static let reviewAndSignButton = String(localized: "Review and Sign", bundle: .module)
    static let unsupportedTokenProgramMessage =
        String(localized: "Unsupported custom token programs are hidden from transfer creation.", bundle: .module)
    static let tokenProgramUnavailableForAsset = String(
        localized: "Token program unavailable for this asset.",
        bundle: .module
    )
    static let unsupportedTokenProgramForTransfer = String(
        localized: "Token program is not supported for transfer creation.",
        bundle: .module
    )
    static let validAmountPrompt = String(localized: "Enter a valid amount.", bundle: .module)
    static let positiveAmountPrompt = String(localized: "Enter an amount greater than zero.", bundle: .module)
    static let assetBalanceUnavailable = String(localized: "Balance unavailable for this asset.", bundle: .module)
    static let amountExceedsBalance = String(localized: "Amount exceeds available balance.", bundle: .module)
    static let validSolanaAddressPrompt = String(localized: "Enter a valid Solana address.", bundle: .module)
    static let recipientValidConfirmation =
        String(localized: "Valid Solana address. You'll get a clear safety read before signing.", bundle: .module)
    static let recipientProgramOwnedTitle = String(localized: "Program-owned address.", bundle: .module)
    static let recipientProgramOwnedBody =
        String(
            localized: "Owned by a program (a token or contract account), not a wallet. SOL sent here is often unrecoverable — confirm with the proposer first.",
            bundle: .module
        )
    static let recipientSquadsControlledTitle = String(localized: "Squads-controlled account.", bundle: .module)
    static let recipientSquadsControlledBody =
        String(
            localized: "A vault or multisig account — funds stay under multisig control. Confirm it's the intended destination.",
            bundle: .module
        )
    static let recipientCheckUnavailableTitle = String(localized: "Couldn't verify recipient.", bundle: .module)
    static let recipientCheckUnavailableBody =
        String(localized: "Owner lookup failed (network) — confirm it's a wallet.", bundle: .module)
    static let recipientVerifiedWalletTitle = String(localized: "Verified wallet.", bundle: .module)
    static let recipientVerifiedWalletBody = String(
        localized: "System-owned account — safe to receive.",
        bundle: .module
    )
    static let recipientMatchesVaultWarning =
        String(
            localized: "Recipient matches the selected vault. Review before proposing this transfer.",
            bundle: .module
        )
    static let submittingProposal = String(localized: "Submitting proposal.", bundle: .module)
    static let loadSquadFirst = String(localized: "Load the Squad first.", bundle: .module)
    static let chooseSigner = String(localized: "Choose a signer.", bundle: .module)
    static let chooseVault = String(localized: "Choose a vault.", bundle: .module)
    static let chooseAsset = String(localized: "Choose an asset.", bundle: .module)
    static let enterRecipientAddress = String(localized: "Enter a recipient address.", bundle: .module)
    static let enterRecipientOwnerAddress = String(localized: "Enter a recipient owner address.", bundle: .module)
    static let enterAmount = String(localized: "Enter an amount.", bundle: .module)
    static let signerNotMemberMessage = String(
        localized: "This signer is not a member of this Squad on the current RPC endpoint.",
        bundle: .module
    )
    static let signerCannotInitiateMessage = String(
        localized: "This signer is a member, but does not have initiate permission.",
        bundle: .module
    )
    static let nativeBalanceSubtitle = String(localized: "Balance (SOL)", bundle: .module)
    static let solAmountLabel = String(localized: "Amount (SOL)", bundle: .module)
    static let splTokenProgramShortTitle = String(localized: "SPL", bundle: .module)
    static let token2022ProgramShortTitle = String(localized: "Token-2022", bundle: .module)
    static let customTokenProgram = String(localized: "Custom token program", bundle: .module)
    static let tokenProgramUnavailable = String(localized: "Token program unavailable", bundle: .module)

    static func amountInputLabel(symbol: String?) -> String {
        guard let symbol else {
            return amountLabel
        }
        return String(localized: "Amount (\(symbol))", bundle: .module)
    }

    static func tokenAssetSubtitle(program: String, balance: String) -> String {
        String(localized: "\(program) · \(balance)", bundle: .module)
    }

    static func builderTitle(squadName: String) -> String {
        String(localized: "New proposal · \(squadName)", bundle: .module)
    }

    static func stepCounter(current: Int, total: Int) -> String {
        "\(current) / \(total)"
    }

    static func amountRouteSubtitle(vaultName: String, recipient: String) -> String {
        String(localized: "From \(vaultName) -> \(recipient)", bundle: .module)
    }
}
