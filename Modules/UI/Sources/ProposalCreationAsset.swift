import Indexer

struct ProposalCreationAsset: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let amountLabel: String
    let rawAmount: String?
    let decimals: UInt8
    let mint: String?
    let tokenProgramID: String?
    let isTransferSupported: Bool

    static let sol = ProposalCreationAsset(
        id: "sol",
        title: CosignCopy.ProposalCreation.solAssetSymbol,
        subtitle: CosignCopy.ProposalCreation.nativeBalanceSubtitle,
        amountLabel: CosignCopy.ProposalCreation.solAmountLabel,
        rawAmount: nil,
        decimals: 9,
        mint: nil,
        tokenProgramID: nil,
        isTransferSupported: true
    )

    init?(asset: DASAsset) {
        guard asset.kind == .fungible, let decimals = asset.decimals else {
            return nil
        }

        let symbol = asset.symbol.flatMap { $0.isEmpty ? nil : $0 }
        let balance = formattedTokenAmount(
            rawAmount: asset.tokenAmount,
            displayAmount: asset.tokenDisplayAmount,
            decimals: asset.decimals
        )
        id = "token:\(asset.tokenProgramID ?? "unknown"):\(asset.id)"
        title = symbol ?? asset.name
        subtitle = CosignCopy.ProposalCreation.tokenAssetSubtitle(
            program: tokenProgramLabel(asset.tokenProgramID),
            balance: balance
        )
        amountLabel = CosignCopy.ProposalCreation.amountInputLabel(symbol: symbol)
        rawAmount = asset.tokenAmount
        self.decimals = decimals
        mint = asset.id
        tokenProgramID = asset.tokenProgramID
        isTransferSupported = Self.isSupportedTokenProgram(asset.tokenProgramID)
    }

    var balanceBaseUnits: UInt64? {
        rawAmount.flatMap(UInt64.init)
    }

    var glyph: CosignGlyph {
        if id == Self.sol.id {
            return .sol
        }
        return .tokenGrid
    }

    var programDetail: String? {
        guard tokenProgramID != nil else {
            return nil
        }
        return tokenProgramLabel(tokenProgramID)
    }

    private init(
        id: String,
        title: String,
        subtitle: String,
        amountLabel: String,
        rawAmount: String?,
        decimals: UInt8,
        mint: String?,
        tokenProgramID: String?,
        isTransferSupported: Bool
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.amountLabel = amountLabel
        self.rawAmount = rawAmount
        self.decimals = decimals
        self.mint = mint
        self.tokenProgramID = tokenProgramID
        self.isTransferSupported = isTransferSupported
    }

    private static func isSupportedTokenProgram(_ tokenProgramID: String?) -> Bool {
        tokenProgramID == HeliusDASClient.tokenProgramID ||
            tokenProgramID == HeliusDASClient.token2022ProgramID
    }
}

func tokenProgramLabel(_ tokenProgramID: String?) -> String {
    switch tokenProgramID {
    case HeliusDASClient.tokenProgramID:
        CosignCopy.ProposalCreation.splTokenProgramShortTitle
    case HeliusDASClient.token2022ProgramID:
        CosignCopy.ProposalCreation.token2022ProgramShortTitle
    case .some:
        CosignCopy.ProposalCreation.customTokenProgram
    case nil:
        CosignCopy.ProposalCreation.tokenProgramUnavailable
    }
}
