import Foundation

struct AssetsByOwnerResponse: Decodable {
    let items: [DASItem]
}

struct TokenAccountsByOwnerResponse: Decodable {
    let value: [TokenAccountItem]
}

struct DASItem: Decodable {
    let id: String
    let interface: String?
    let content: DASItemContent?
    let tokenInfo: DASItemTokenInfo?

    enum CodingKeys: String, CodingKey {
        case id
        case interface
        case content
        case tokenInfo = "token_info"
    }
}

struct DASItemContent: Decodable {
    let metadata: DASItemMetadata?
    let links: DASItemLinks?
}

struct DASItemMetadata: Decodable {
    let name: String?
    let symbol: String?
}

struct DASItemLinks: Decodable {
    let image: String?
}

struct TokenAccountItem: Decodable {
    let pubkey: String
    let account: TokenAccountRecord
}

struct TokenAccountRecord: Decodable {
    let data: TokenAccountData
}

struct TokenAccountData: Decodable {
    let parsed: ParsedTokenAccount?
    let program: String?
}

struct ParsedTokenAccount: Decodable {
    let info: TokenAccountInfo
}

struct TokenAccountInfo: Decodable {
    let mint: String
    let tokenAmount: TokenAmount
}

struct TokenAmount: Decodable {
    let amount: FlexibleString
    let decimals: UInt8
    let uiAmount: FlexibleString?
    let uiAmountString: FlexibleString?
}

struct DASItemTokenInfo: Decodable {
    let symbol: String?
    let balance: FlexibleString?
    let decimals: UInt8?
    let tokenAmount: FlexibleString?
    let uiAmount: FlexibleString?
    let uiAmountString: FlexibleString?
    let tokenProgram: String?

    enum CodingKeys: String, CodingKey {
        case symbol
        case balance
        case decimals
        case tokenAmount = "token_amount"
        case uiAmountSnake = "ui_amount"
        case uiAmountStringSnake = "ui_amount_string"
        case uiAmountCamel = "uiAmount"
        case uiAmountStringCamel = "uiAmountString"
        case tokenProgramSnake = "token_program"
        case tokenProgramCamel = "tokenProgram"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        balance = try container.decodeIfPresent(FlexibleString.self, forKey: .balance)
        decimals = try container.decodeIfPresent(UInt8.self, forKey: .decimals)
        tokenAmount = try container.decodeIfPresent(FlexibleString.self, forKey: .tokenAmount)
        uiAmount = try container.decodeIfPresent(FlexibleString.self, forKey: .uiAmountSnake)
            ?? container.decodeIfPresent(FlexibleString.self, forKey: .uiAmountCamel)
        uiAmountString = try container.decodeIfPresent(FlexibleString.self, forKey: .uiAmountStringSnake)
            ?? container.decodeIfPresent(FlexibleString.self, forKey: .uiAmountStringCamel)
        tokenProgram = try container.decodeIfPresent(String.self, forKey: .tokenProgramSnake)
            ?? container.decodeIfPresent(String.self, forKey: .tokenProgramCamel)
    }
}

extension DASAsset {
    init(item: DASItem) {
        let metadata = item.content?.metadata
        let tokenInfo = item.tokenInfo
        let imageURI = item.content?.links?.image.flatMap(URL.init(string:))
        let interface = item.interface?.lowercased() ?? ""
        let isFungible = interface.contains("fungible")

        self.init(
            id: item.id,
            symbol: tokenInfo?.symbol ?? metadata?.symbol,
            name: metadata?.name ?? tokenInfo?.symbol ?? item.id,
            tokenAmount: tokenInfo?.tokenAmount?.value ?? tokenInfo?.balance?.value,
            tokenDisplayAmount: tokenInfo?.uiAmountString?.value ?? tokenInfo?.uiAmount?.value,
            decimals: tokenInfo?.decimals,
            tokenProgramID: tokenInfo?.tokenProgram.flatMap(Self.tokenProgramID(from:)),
            imageURI: imageURI,
            kind: isFungible ? .fungible : .nft
        )
    }

    init?(tokenAccount item: TokenAccountItem) {
        guard let parsed = item.account.data.parsed else {
            return nil
        }

        let info = parsed.info
        let amount = info.tokenAmount.amount.value
        guard amount != "0" else {
            return nil
        }

        self.init(
            id: info.mint,
            symbol: nil,
            name: info.mint,
            tokenAmount: amount,
            tokenDisplayAmount: info.tokenAmount.uiAmountString?.value ?? info.tokenAmount.uiAmount?.value,
            decimals: info.tokenAmount.decimals,
            accountAddress: item.pubkey,
            tokenProgramID: Self.tokenProgramID(from: item.account.data.program),
            imageURI: nil,
            kind: .fungible
        )
    }

    static func tokenProgramID(from program: String?) -> String? {
        switch program {
        case "spl-token", HeliusDASClient.tokenProgramID:
            HeliusDASClient.tokenProgramID
        case "spl-token-2022", HeliusDASClient.token2022ProgramID:
            HeliusDASClient.token2022ProgramID
        default:
            program
        }
    }
}

struct FlexibleString: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = String(int)
        } else if let double = try? container.decode(Double.self) {
            value = String(double)
        } else {
            value = ""
        }
    }
}
