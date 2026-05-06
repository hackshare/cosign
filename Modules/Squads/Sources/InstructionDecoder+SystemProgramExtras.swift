extension InstructionDecoder {
    func decodeCreateAccountWithSeed(
        _ instruction: SquadDecodedInstruction,
        data: [UInt8],
        accounts: [String]
    ) -> DecodedInstructionDisplay {
        guard
            let seed = Self.bincodeString(data, at: 36),
            let lamports = Self.uint64(data, at: seed.nextOffset),
            let space = Self.uint64(data, at: seed.nextOffset + 8),
            let owner = Self.pubkey(data, at: seed.nextOffset + 16)
        else {
            return fallback(instruction, accounts: accounts)
        }

        let isNonce = Self.isNonceAccountCreation(space: space, owner: owner)
        return systemDisplay(
            instruction,
            kind: isNonce ? "create_nonce_account_with_seed" : "create_account_with_seed",
            summary: isNonce
                ? "Create seeded nonce account with \(Self.solAmount(lamports))"
                : "Create seeded account with \(Self.solAmount(lamports)), \(space) bytes, owner \(owner)",
            accounts: accounts
        )
    }

    func decodeWithdrawNonce(
        _ instruction: SquadDecodedInstruction,
        data: [UInt8],
        accounts: [String]
    ) -> DecodedInstructionDisplay {
        guard let lamports = Self.uint64(data, at: 4) else {
            return fallback(instruction, accounts: accounts)
        }

        return systemDisplay(
            instruction,
            kind: "withdraw_nonce_account",
            summary: "Withdraw \(Self.solAmount(lamports)) from nonce account",
            accounts: accounts
        )
    }

    func decodeAllocate(
        _ instruction: SquadDecodedInstruction,
        data: [UInt8],
        accounts: [String],
        kind: String,
        summaryPrefix: String
    ) -> DecodedInstructionDisplay {
        guard let space = Self.uint64(data, at: 4) else {
            return fallback(instruction, accounts: accounts)
        }

        return systemDisplay(
            instruction,
            kind: kind,
            summary: "\(summaryPrefix) \(space) bytes for system account",
            accounts: accounts
        )
    }

    func decodeAllocateWithSeed(
        _ instruction: SquadDecodedInstruction,
        data: [UInt8],
        accounts: [String]
    ) -> DecodedInstructionDisplay {
        guard
            let seed = Self.bincodeString(data, at: 36),
            let space = Self.uint64(data, at: seed.nextOffset),
            let owner = Self.pubkey(data, at: seed.nextOffset + 8)
        else {
            return fallback(instruction, accounts: accounts)
        }

        return systemDisplay(
            instruction,
            kind: "allocate_with_seed",
            summary: "Allocate \(space) bytes for seeded account owned by \(owner)",
            accounts: accounts
        )
    }

    func decodeTransferWithSeed(
        _ instruction: SquadDecodedInstruction,
        data: [UInt8],
        accounts: [String]
    ) -> DecodedInstructionDisplay {
        guard let lamports = Self.uint64(data, at: 4) else {
            return fallback(instruction, accounts: accounts)
        }

        return systemDisplay(
            instruction,
            kind: "transfer_with_seed",
            summary: "Transfer \(Self.solAmount(lamports)) from seeded account",
            accounts: accounts
        )
    }
}
