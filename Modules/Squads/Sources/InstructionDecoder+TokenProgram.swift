import Foundation

extension InstructionDecoder {
    struct TokenOptionalPubkey {
        let value: String?
    }

    func decodeTokenInstruction(
        _ instruction: SquadDecodedInstruction,
        data: [UInt8],
        accounts: [String]
    ) -> DecodedInstructionDisplay {
        guard let metadata = Self.tokenInstructionMetadata(data: data, accounts: accounts) else {
            return fallback(instruction, accounts: accounts)
        }

        return DecodedInstructionDisplay(
            programLabel: Self.programLabel(for: instruction.program),
            kind: metadata.kind,
            summary: metadata.summary,
            accounts: accounts,
            dataHex: instruction.rawDataHex
        )
    }

    static func tokenInstructionMetadata(
        data: [UInt8],
        accounts: [String]
    ) -> (kind: String, summary: String)? {
        guard let discriminator = data.first else {
            return nil
        }

        if let metadata = tokenBaseInstructionMetadata(discriminator, data: data, accounts: accounts) {
            return metadata
        }
        if let metadata = tokenCheckedInstructionMetadata(discriminator, data: data, accounts: accounts) {
            return metadata
        }
        return tokenInitializationMetadata(discriminator, data: data)
    }

    static func tokenBaseInstructionMetadata(
        _ discriminator: UInt8,
        data: [UInt8],
        accounts: [String]
    ) -> (kind: String, summary: String)? {
        switch discriminator {
        case 3:
            tokenTransferMetadata(data: data, accounts: accounts)
        case 4:
            tokenApproveMetadata(data: data, accounts: accounts)
        case 5:
            ("revoke", "Revoke token delegate")
        case 6:
            tokenSetAuthorityMetadata(data: data)
        case 7:
            tokenMintMetadata(data: data, accounts: accounts)
        case 8:
            tokenBurnMetadata(data: data, accounts: accounts)
        case 9:
            (
                "close_account",
                tokenAccountActionSummary("Close token account", account: account(at: 0, in: accounts))
            )
        case 10:
            (
                "freeze_account",
                tokenAccountActionSummary("Freeze token account", account: account(at: 0, in: accounts))
            )
        case 11:
            (
                "thaw_account",
                tokenAccountActionSummary("Thaw token account", account: account(at: 0, in: accounts))
            )
        default:
            nil
        }
    }

    static func tokenCheckedInstructionMetadata(
        _ discriminator: UInt8,
        data: [UInt8],
        accounts: [String]
    ) -> (kind: String, summary: String)? {
        switch discriminator {
        case 12:
            tokenCheckedTransferMetadata(data: data, accounts: accounts)
        case 13:
            tokenCheckedApproveMetadata(data: data, accounts: accounts)
        case 14:
            tokenCheckedMintMetadata(data: data, accounts: accounts)
        case 15:
            tokenCheckedBurnMetadata(data: data, accounts: accounts)
        default:
            nil
        }
    }

    static func tokenInitializationMetadata(
        _ discriminator: UInt8,
        data: [UInt8]
    ) -> (kind: String, summary: String)? {
        switch discriminator {
        case 0:
            initializeMintMetadata(data: data)
        case 16:
            tokenAccountOwnerMetadata(kind: "initialize_account2", data: data)
        case 18:
            tokenAccountOwnerMetadata(kind: "initialize_account3", data: data)
        case 20:
            initializeMintMetadata(data: data, kind: "initialize_mint2")
        case 22:
            ("initialize_immutable_owner", "Initialize immutable token account owner")
        default:
            nil
        }
    }

    static func tokenTransferMetadata(data: [UInt8], accounts: [String]) -> (kind: String, summary: String)? {
        guard let amount = uint64(data, at: 1) else {
            return nil
        }

        return (
            "transfer",
            tokenTransferSummary(amount: "\(amount) base units", recipient: account(at: 1, in: accounts))
        )
    }

    static func tokenCheckedTransferMetadata(data: [UInt8], accounts: [String]) -> (kind: String, summary: String)? {
        guard let amount = checkedTokenAmount(data) else {
            return nil
        }

        return (
            "transfer_checked",
            tokenTransferSummary(amount: amount, recipient: account(at: 2, in: accounts))
        )
    }

    static func tokenApproveMetadata(data: [UInt8], accounts: [String]) -> (kind: String, summary: String)? {
        guard let amount = uint64(data, at: 1) else {
            return nil
        }

        return (
            "approve",
            tokenRecipientSummary(
                "\(amount) base units",
                verb: "Approve",
                preposition: "for",
                recipient: account(at: 1, in: accounts)
            )
        )
    }

    static func tokenCheckedApproveMetadata(data: [UInt8], accounts: [String]) -> (kind: String, summary: String)? {
        guard let amount = checkedTokenAmount(data) else {
            return nil
        }

        return (
            "approve_checked",
            tokenRecipientSummary(
                amount,
                verb: "Approve",
                preposition: "for",
                recipient: account(at: 2, in: accounts)
            )
        )
    }

    static func tokenSetAuthorityMetadata(data: [UInt8]) -> (kind: String, summary: String)? {
        guard data.count >= 6 else {
            return nil
        }

        let authorityType = tokenAuthorityTypeLabel(data[1])
        guard let newAuthority = coptionPubkey(data, at: 2) else {
            return nil
        }
        let summary = if let authority = newAuthority.value {
            "Set token \(authorityType) to \(authority)"
        } else {
            "Clear token \(authorityType)"
        }

        return ("set_authority", summary)
    }

    static func tokenMintMetadata(data: [UInt8], accounts: [String]) -> (kind: String, summary: String)? {
        guard let amount = uint64(data, at: 1) else {
            return nil
        }

        return (
            "mint_to",
            tokenRecipientSummary(
                "\(amount) base units",
                verb: "Mint",
                preposition: "to",
                recipient: account(at: 1, in: accounts)
            )
        )
    }

    static func tokenCheckedMintMetadata(data: [UInt8], accounts: [String]) -> (kind: String, summary: String)? {
        guard let amount = checkedTokenAmount(data) else {
            return nil
        }

        return (
            "mint_to_checked",
            tokenRecipientSummary(amount, verb: "Mint", preposition: "to", recipient: account(at: 1, in: accounts))
        )
    }

    static func tokenBurnMetadata(data: [UInt8], accounts: [String]) -> (kind: String, summary: String)? {
        guard let amount = uint64(data, at: 1) else {
            return nil
        }

        return (
            "burn",
            tokenRecipientSummary(
                "\(amount) base units",
                verb: "Burn",
                preposition: "from",
                recipient: account(at: 0, in: accounts)
            )
        )
    }

    static func tokenCheckedBurnMetadata(data: [UInt8], accounts: [String]) -> (kind: String, summary: String)? {
        guard let amount = checkedTokenAmount(data) else {
            return nil
        }

        return (
            "burn_checked",
            tokenRecipientSummary(amount, verb: "Burn", preposition: "from", recipient: account(at: 0, in: accounts))
        )
    }

    static func initializeMintMetadata(
        data: [UInt8],
        kind: String = "initialize_mint"
    ) -> (kind: String, summary: String)? {
        guard
            data.count >= 34,
            let mintAuthority = pubkey(data, at: 2),
            let freezeAuthority = coptionPubkey(data, at: 34)
        else {
            return nil
        }

        let freezeSummary = freezeAuthority.value.map { ", freeze authority \($0)" } ?? ", no freeze authority"
        return (
            kind,
            "Initialize mint with \(data[1]) decimals, mint authority \(mintAuthority)\(freezeSummary)"
        )
    }

    static func tokenAccountOwnerMetadata(kind: String, data: [UInt8]) -> (kind: String, summary: String)? {
        guard let owner = pubkey(data, at: 1) else {
            return nil
        }

        return (kind, "Initialize token account for owner \(owner)")
    }

    static func checkedTokenAmount(_ data: [UInt8]) -> String? {
        guard data.count >= 10, let amount = uint64(data, at: 1) else {
            return nil
        }

        return "\(decimalAmount(amount, decimals: data[9])) tokens"
    }

    static func tokenTransferSummary(amount: String, recipient: String?) -> String {
        tokenRecipientSummary(amount, verb: "Transfer", preposition: "to", recipient: recipient)
    }

    static func tokenRecipientSummary(
        _ amount: String,
        verb: String,
        preposition: String,
        recipient: String?
    ) -> String {
        guard let recipient else {
            return "\(verb) \(amount)"
        }
        return "\(verb) \(amount) \(preposition) \(shortAddress(recipient))"
    }

    static func tokenAccountActionSummary(_ action: String, account: String?) -> String {
        guard let account else {
            return action
        }
        return "\(action) \(shortAddress(account))"
    }

    static func tokenAuthorityTypeLabel(_ value: UInt8) -> String {
        switch value {
        case 0:
            "mint authority"
        case 1:
            "freeze authority"
        case 2:
            "account owner"
        case 3:
            "close authority"
        default:
            "authority"
        }
    }

    static func coptionPubkey(_ bytes: [UInt8], at offset: Int) -> TokenOptionalPubkey? {
        guard let tag = uint32(bytes, at: offset) else {
            return nil
        }

        if tag == 0 {
            return TokenOptionalPubkey(value: nil)
        }

        guard tag == 1, let value = pubkey(bytes, at: offset + 4) else {
            return nil
        }
        return TokenOptionalPubkey(value: value)
    }
}
