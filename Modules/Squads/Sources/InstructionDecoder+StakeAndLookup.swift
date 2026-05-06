extension InstructionDecoder {
    func decodeStakeInstruction(
        _ instruction: SquadDecodedInstruction,
        data: [UInt8],
        accounts: [String]
    ) -> DecodedInstructionDisplay {
        guard let discriminator = Self.uint32(data, at: 0) else {
            return fallback(instruction, accounts: accounts)
        }

        guard let metadata = decodeStakeAuthorityMetadata(
            discriminator,
            data: data,
            accounts: accounts
        ) ?? decodeStakeMovementMetadata(
            discriminator,
            data: data,
            accounts: accounts
        ) ?? decodeStakeLifecycleMetadata(
            discriminator,
            data: data,
            accounts: accounts
        ) else {
            return fallback(instruction, accounts: accounts)
        }

        return programDisplay(
            instruction,
            programLabel: "Stake Program",
            kind: metadata.kind,
            summary: metadata.summary,
            accounts: accounts
        )
    }

    func decodeStakeAuthorityMetadata(
        _ discriminator: UInt32,
        data: [UInt8],
        accounts: [String]
    ) -> (kind: String, summary: String)? {
        switch discriminator {
        case 1:
            decodeStakeAuthorize(data: data, accounts: accounts)
        case 8:
            decodeStakeAuthorizeWithSeed(data: data)
        case 10:
            decodeStakeAuthorizeChecked(data: data, accounts: accounts)
        case 11:
            decodeStakeAuthorizeCheckedWithSeed(data: data, accounts: accounts)
        default:
            nil
        }
    }

    func decodeStakeMovementMetadata(
        _ discriminator: UInt32,
        data: [UInt8],
        accounts: [String]
    ) -> (kind: String, summary: String)? {
        switch discriminator {
        case 2:
            ("stake_delegate", "Delegate stake\(Self.accountSuffix(at: 1, in: accounts, prefix: " to "))")
        case 3:
            decodeStakeLamports(data: data, kind: "stake_split", verb: "Split", suffix: " stake")
        case 4:
            decodeStakeLamports(data: data, kind: "stake_withdraw", verb: "Withdraw", suffix: " from stake")
        case 7:
            ("stake_merge", "Merge stake accounts")
        case 15:
            ("stake_redelegate", "Redelegate stake\(Self.accountSuffix(at: 2, in: accounts, prefix: " to "))")
        default:
            nil
        }
    }

    func decodeStakeLifecycleMetadata(
        _ discriminator: UInt32,
        data: [UInt8],
        accounts: [String]
    ) -> (kind: String, summary: String)? {
        switch discriminator {
        case 0:
            decodeStakeInitialize(data: data, accounts: accounts)
        case 5:
            ("stake_deactivate", "Deactivate stake")
        case 6, 12:
            ("stake_lockup_change", "Set stake lockup")
        case 9:
            Self.checkedStakeInitializeMetadata(accounts: accounts)
        case 13:
            ("stake_minimum_delegation", "Get minimum stake delegation")
        case 14:
            (
                "stake_deactivate",
                "Deactivate delinquent stake\(Self.accountSuffix(at: 1, in: accounts, prefix: " for vote account "))"
            )
        default:
            nil
        }
    }

    func decodeAddressLookupTableInstruction(
        _ instruction: SquadDecodedInstruction,
        data: [UInt8],
        accounts: [String]
    ) -> DecodedInstructionDisplay {
        guard let discriminator = Self.uint32(data, at: 0) else {
            return fallback(instruction, accounts: accounts)
        }

        let metadata: (kind: String, summary: String)? = switch discriminator {
        case 0:
            (
                "lookup_table_create",
                "Create address lookup table\(Self.lookupTableSlotSummary(data: data))"
            )
        case 1:
            ("lookup_table_freeze", "Freeze address lookup table")
        case 2:
            decodeLookupTableExtend(data: data)
        case 3:
            ("lookup_table_deactivate", "Deactivate address lookup table")
        case 4:
            ("lookup_table_close", "Close address lookup table")
        default:
            nil
        }

        guard let metadata else {
            return fallback(instruction, accounts: accounts)
        }

        return programDisplay(
            instruction,
            programLabel: "Address Lookup Table Program",
            kind: metadata.kind,
            summary: metadata.summary,
            accounts: accounts
        )
    }

    func decodeStakeInitialize(
        data: [UInt8],
        accounts: [String]
    ) -> (kind: String, summary: String)? {
        guard let staker = Self.pubkey(data, at: 4), let withdrawer = Self.pubkey(data, at: 36) else {
            return nil
        }

        return (
            "stake_initialize",
            "Initialize stake account\(Self.accountSuffix(at: 0, in: accounts, prefix: " ")) with staker \(staker) and withdrawer \(withdrawer)"
        )
    }

    static func checkedStakeInitializeMetadata(accounts: [String]) -> (kind: String, summary: String) {
        (
            "stake_initialize",
            "Initialize stake account with staker \(account(at: 2, in: accounts) ?? "stake authority") and withdrawer \(account(at: 3, in: accounts) ?? "withdraw authority")"
        )
    }

    func decodeStakeAuthorize(
        data: [UInt8],
        accounts _: [String]
    ) -> (kind: String, summary: String)? {
        guard let authority = Self.pubkey(data, at: 4), let authorityType = Self.uint32(data, at: 36) else {
            return nil
        }

        return (
            "stake_authority_change",
            "Set stake \(Self.stakeAuthorityLabel(authorityType)) authority to \(authority)"
        )
    }

    func decodeStakeAuthorizeWithSeed(data: [UInt8]) -> (kind: String, summary: String)? {
        guard let authority = Self.pubkey(data, at: 4), let authorityType = Self.uint32(data, at: 36) else {
            return nil
        }

        return (
            "stake_authority_change",
            "Set stake \(Self.stakeAuthorityLabel(authorityType)) authority to \(authority)"
        )
    }

    func decodeStakeAuthorizeChecked(
        data: [UInt8],
        accounts: [String]
    ) -> (kind: String, summary: String)? {
        guard let authorityType = Self.uint32(data, at: 4) else {
            return nil
        }

        return (
            "stake_authority_change",
            "Set stake \(Self.stakeAuthorityLabel(authorityType)) authority to \(Self.account(at: 3, in: accounts) ?? "new authority")"
        )
    }

    func decodeStakeAuthorizeCheckedWithSeed(
        data: [UInt8],
        accounts: [String]
    ) -> (kind: String, summary: String)? {
        guard let authorityType = Self.uint32(data, at: 4) else {
            return nil
        }

        return (
            "stake_authority_change",
            "Set stake \(Self.stakeAuthorityLabel(authorityType)) authority to \(Self.account(at: 3, in: accounts) ?? "new authority")"
        )
    }

    func decodeStakeLamports(
        data: [UInt8],
        kind: String,
        verb: String,
        suffix: String
    ) -> (kind: String, summary: String)? {
        guard let lamports = Self.uint64(data, at: 4) else {
            return nil
        }

        return (kind, "\(verb) \(Self.solAmount(lamports))\(suffix)")
    }

    func decodeLookupTableExtend(data: [UInt8]) -> (kind: String, summary: String)? {
        guard let addressCount = Self.uint64(data, at: 4) else {
            return nil
        }

        return (
            "lookup_table_extend",
            "Extend address lookup table with \(Self.addressCountLabel(Int(addressCount)))"
        )
    }

    func programDisplay(
        _ instruction: SquadDecodedInstruction,
        programLabel: String,
        kind: String,
        summary: String,
        accounts: [String]
    ) -> DecodedInstructionDisplay {
        DecodedInstructionDisplay(
            programLabel: programLabel,
            kind: kind,
            summary: summary,
            accounts: accounts,
            dataHex: instruction.rawDataHex
        )
    }

    static func isStakeProgram(_ program: String) -> Bool {
        program == stakeProgramID || program == "Stake Program" || program == "stake"
    }

    static func isAddressLookupTableProgram(_ program: String) -> Bool {
        program == addressLookupTableProgramID || program == "Address Lookup Table Program" ||
            program == "address-lookup-table"
    }

    static func stakeAuthorityLabel(_ value: UInt32) -> String {
        switch value {
        case 1:
            "withdraw"
        default:
            "staker"
        }
    }

    static func addressCountLabel(_ count: Int) -> String {
        count == 1 ? "1 address" : "\(count) addresses"
    }

    static func lookupTableSlotSummary(data: [UInt8]) -> String {
        guard let slot = uint64(data, at: 4) else {
            return ""
        }
        return " using recent slot \(slot)"
    }

    static func accountSuffix(at index: Int, in accounts: [String], prefix: String) -> String {
        guard let account = account(at: index, in: accounts) else {
            return ""
        }
        return "\(prefix)\(account)"
    }
}
