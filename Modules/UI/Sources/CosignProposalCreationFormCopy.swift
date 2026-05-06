extension CosignCopy.ProposalCreation {
    static let newProposalSection = "New proposal"
    static let transferTitle = "Transfer"
    static let unableToLoadSquadTitle = "Unable to Load Squad"
    static let retryButton = "Retry"
    static let createTransferNavigationTitle = "Create Transfer"
    static let selectVaultTitle = "Select vault"
    static let selectSignerTitle = "Select signer"
    static let selectAssetTitle = "Select asset"
    static let selectSignerSubtitle = "Choose the local signer that creates this proposal."
    static let selectVaultSubtitle = "Choose the vault that will send funds if the proposal executes."
    static let selectAssetSubtitle = "Choose the asset to transfer from the selected vault."
    static let vaultAssetStepHeadline = "What are you moving?"
    static let vaultAssetStepSubtitle = "Choose the source vault and asset. We'll route the rest."
    static let recipientStepHeadline = "Where is it going?"
    static let recipientStepSubtitle = "Paste a Solana address, scan a QR code, or choose a known recipient."
    static let amountStepHeadline = "How much?"
    static let amountStepSubtitle = "Enter the amount and an optional memo for the proposal."
    static let reviewStepHeadline = "Review proposal"
    static let reviewStepSubtitle = "This is exactly what other signers will see."
    static let fromVaultLabel = "From vault"
    static let nextButton = "Next"
    static let backButton = "Back"
    static let pasteButton = "Paste"
    static let scanQRButton = "Scan QR"
    static let knownRecipientButton = "Known"
    static let maxAmountButton = "Max"
    static let recipientAddressPlaceholder = "Recipient address"
    static let recipientOwnerAddressPlaceholder = "Recipient owner address"
    static let clearRecipientAddressAccessibilityLabel = "Clear Recipient Address"
    static let pasteRecipientAddressAccessibilityLabel = "Paste Recipient Address"
    static let clearAmountAccessibilityLabel = "Clear Amount"
    static let optionalMemoPlaceholder = "Optional memo"
    static let reviewAndSignButton = "Review and Sign"
    static let unsupportedTokenProgramMessage =
        "Unsupported custom token programs are hidden from transfer creation."
    static let tokenProgramUnavailableForAsset = "Token program unavailable for this asset."
    static let unsupportedTokenProgramForTransfer = "Token program is not supported for transfer creation."
    static let validAmountPrompt = "Enter a valid amount."
    static let positiveAmountPrompt = "Enter an amount greater than zero."
    static let assetBalanceUnavailable = "Balance unavailable for this asset."
    static let amountExceedsBalance = "Amount exceeds available balance."
    static let validSolanaAddressPrompt = "Enter a valid Solana address."
    static let recipientValidConfirmation =
        "Valid Solana address. You'll get a clear safety read before signing."
    static let recipientProgramOwnedTitle = "Program-owned address."
    static let recipientProgramOwnedBody =
        "Owned by a program (a token or contract account), not a wallet. "
            + "SOL sent here is often unrecoverable — confirm with the proposer first."
    static let recipientSquadsControlledTitle = "Squads-controlled account."
    static let recipientSquadsControlledBody =
        "A vault or multisig account — funds stay under multisig control. "
            + "Confirm it's the intended destination."
    static let recipientCheckUnavailableTitle = "Couldn't verify recipient."
    static let recipientCheckUnavailableBody =
        "Owner lookup failed (network) — confirm it's a wallet."
    static let recipientVerifiedWalletTitle = "Verified wallet."
    static let recipientVerifiedWalletBody = "System-owned account — safe to receive."
    static let recipientMatchesVaultWarning =
        "Recipient matches the selected vault. Review before proposing this transfer."
    static let submittingProposal = "Submitting proposal."
    static let loadSquadFirst = "Load the Squad first."
    static let chooseSigner = "Choose a signer."
    static let chooseVault = "Choose a vault."
    static let chooseAsset = "Choose an asset."
    static let enterRecipientAddress = "Enter a recipient address."
    static let enterRecipientOwnerAddress = "Enter a recipient owner address."
    static let enterAmount = "Enter an amount."
    static let signerNotMemberMessage = "This signer is not a member of this Squad on the current RPC endpoint."
    static let signerCannotInitiateMessage = "This signer is a member, but does not have initiate permission."
    static let nativeBalanceSubtitle = "Balance (SOL)"
    static let solAmountLabel = "Amount (SOL)"
    static let splTokenProgramShortTitle = "SPL"
    static let token2022ProgramShortTitle = "Token-2022"
    static let customTokenProgram = "Custom token program"
    static let tokenProgramUnavailable = "Token program unavailable"

    static func amountInputLabel(symbol: String?) -> String {
        guard let symbol else {
            return amountLabel
        }
        return "Amount (\(symbol))"
    }

    static func tokenAssetSubtitle(program: String, balance: String) -> String {
        "\(program) · \(balance)"
    }

    static func builderTitle(squadName: String) -> String {
        "New proposal · \(squadName)"
    }

    static func stepCounter(current: Int, total: Int) -> String {
        "\(current) / \(total)"
    }

    static func amountRouteSubtitle(vaultName: String, recipient: String) -> String {
        "From \(vaultName) -> \(recipient)"
    }
}
