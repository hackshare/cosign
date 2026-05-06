import Foundation

public struct DecodedInstructionDisplay: Equatable, Sendable {
    public let programLabel: String
    public let kind: String
    public let summary: String
    public let accounts: [String]
    public let dataHex: String

    public init(
        programLabel: String,
        kind: String,
        summary: String,
        accounts: [String],
        dataHex: String
    ) {
        self.programLabel = programLabel
        self.kind = kind
        self.summary = summary
        self.accounts = accounts
        self.dataHex = dataHex
    }
}

public struct InstructionDecoder: Sendable {
    public init() {}

    public func decode(
        _ instruction: SquadDecodedInstruction,
        accounts overrideAccounts: [String]? = nil
    ) -> DecodedInstructionDisplay {
        let accounts = overrideAccounts ?? instruction.accounts

        guard let data = Self.bytes(fromHex: instruction.rawDataHex) else {
            return fallback(instruction, accounts: accounts)
        }

        if Self.isSystemProgram(instruction.program) {
            return decodeSystemInstruction(instruction, data: data, accounts: accounts)
        }

        if Self.isTokenProgram(instruction.program) {
            return decodeTokenInstruction(instruction, data: data, accounts: accounts)
        }

        if Self.isStakeProgram(instruction.program) {
            return decodeStakeInstruction(instruction, data: data, accounts: accounts)
        }

        if Self.isAddressLookupTableProgram(instruction.program) {
            return decodeAddressLookupTableInstruction(instruction, data: data, accounts: accounts)
        }

        if Self.isAssociatedTokenAccountProgram(instruction.program) {
            return decodeAssociatedTokenAccountInstruction(instruction, data: data, accounts: accounts)
        }

        if Self.isMemoProgram(instruction.program) {
            return decodeMemoInstruction(instruction, data: data, accounts: accounts)
        }

        if Self.isComputeBudgetProgram(instruction.program) {
            return decodeComputeBudgetInstruction(instruction, data: data, accounts: accounts)
        }

        if Self.isUpgradeableLoaderProgram(instruction.program) {
            return decodeUpgradeableLoaderInstruction(instruction, data: data, accounts: accounts)
        }

        if Self.isSquadsProgram(instruction.program) {
            return decodeSquadsInstruction(instruction, accounts: accounts)
        }

        return fallback(instruction, accounts: accounts)
    }

    public func decode(_ proposal: SquadProposalDetail) -> [DecodedInstructionDisplay] {
        proposal.instructions.map { instruction in
            let accounts = instruction.accounts.isEmpty ? proposal.accountsReferenced : instruction.accounts
            return decode(instruction, accounts: accounts)
        }
    }
}

extension InstructionDecoder {
    static let systemProgramID = "11111111111111111111111111111111"
    static let tokenProgramID = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
    static let token2022ProgramID = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"
    static let stakeProgramID = "Stake11111111111111111111111111111111111111"
    static let addressLookupTableProgramID = "AddressLookupTab1e1111111111111111111111111"
    static let squadsProgramID = "SQDS4ep65T869zMMBKyuUq6aD6EgTu8psMjkvj52pCf"
    static let lamportsPerSOL: UInt64 = 1_000_000_000

    func decodeSquadsInstruction(
        _ instruction: SquadDecodedInstruction,
        accounts: [String]
    ) -> DecodedInstructionDisplay {
        let kind = instruction.kind.isEmpty ? "config" : instruction.kind
        let summary = instruction.summary.isEmpty ? Self.squadsSummary(for: kind) : instruction.summary
        return DecodedInstructionDisplay(
            programLabel: "Squads",
            kind: kind,
            summary: summary,
            accounts: accounts,
            dataHex: instruction.rawDataHex
        )
    }

    func fallback(
        _ instruction: SquadDecodedInstruction,
        accounts: [String]
    ) -> DecodedInstructionDisplay {
        let programLabel = Self.programLabel(for: instruction.program)
        let kind = instruction.kind.isEmpty ? "raw" : instruction.kind
        let summary = instruction.summary.isEmpty ? "Instruction for \(programLabel)" : instruction.summary
        return DecodedInstructionDisplay(
            programLabel: programLabel,
            kind: kind,
            summary: summary,
            accounts: accounts,
            dataHex: instruction.rawDataHex
        )
    }

    static func isTokenProgram(_ program: String) -> Bool {
        program == tokenProgramID || program == token2022ProgramID || program == "SPL Token Program" ||
            program == "Token-2022 Program"
    }

    static func isSquadsProgram(_ program: String) -> Bool {
        program == squadsProgramID || program == "Squads"
    }

    static func programLabel(for program: String) -> String {
        if let label = knownProgramLabels[program] {
            return label
        }
        return program
    }

    static let knownProgramLabels = [
        systemProgramID: "System Program",
        tokenProgramID: "SPL Token Program",
        token2022ProgramID: "Token-2022 Program",
        stakeProgramID: "Stake Program",
        addressLookupTableProgramID: "Address Lookup Table Program",
        associatedTokenAccountProgramID: "Associated Token Account Program",
        memoProgramID: "Memo Program",
        memoLegacyProgramID: "Memo Program",
        computeBudgetProgramID: "Compute Budget Program",
        squadsProgramID: "Squads",
        bpfUpgradeableLoaderProgramID: "BPF Upgradeable Loader"
    ]

    static func account(at index: Int, in accounts: [String]) -> String? {
        guard accounts.indices.contains(index) else {
            return nil
        }
        return accounts[index]
    }

    static func shortAddress(_ address: String) -> String {
        guard address.count > 16 else {
            return address
        }
        return "\(address.prefix(6))...\(address.suffix(6))"
    }

    static func squadsSummary(for kind: String) -> String {
        switch kind {
        case "add_member":
            "Add member"
        case "remove_member":
            "Remove member"
        case "change_threshold":
            "Change threshold"
        case "set_time_lock":
            "Set time lock"
        case "add_spending_limit":
            "Add spending limit"
        case "remove_spending_limit":
            "Remove spending limit"
        case "set_rent_collector":
            "Set rent collector"
        default:
            "Squads config action"
        }
    }

    static func bytes(fromHex hex: String) -> [UInt8]? {
        let normalized = hex
            .filter { !$0.isWhitespace }
            .lowercased()
        guard normalized.count.isMultiple(of: 2) else {
            return nil
        }

        var bytes = [UInt8]()
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let nextIndex = normalized.index(index, offsetBy: 2)
            guard let byte = UInt8(normalized[index ..< nextIndex], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = nextIndex
        }
        return bytes
    }

    static func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32? {
        guard bytes.count >= offset + 4 else {
            return nil
        }

        var value: UInt32 = 0
        for index in 0 ..< 4 {
            value |= UInt32(bytes[offset + index]) << (index * 8)
        }
        return value
    }

    static func uint64(_ bytes: [UInt8], at offset: Int) -> UInt64? {
        guard bytes.count >= offset + 8 else {
            return nil
        }

        var value: UInt64 = 0
        for index in 0 ..< 8 {
            value |= UInt64(bytes[offset + index]) << (index * 8)
        }
        return value
    }

    static func decimalAmount(_ amount: UInt64, decimals: UInt8) -> String {
        guard decimals > 0 else {
            return String(amount)
        }

        let decimalCount = Int(decimals)
        let digits = String(amount)
        let paddedDigits: String = if digits.count <= decimalCount {
            String(repeating: "0", count: decimalCount - digits.count + 1) + digits
        } else {
            digits
        }

        let splitIndex = paddedDigits.index(paddedDigits.endIndex, offsetBy: -decimalCount)
        let whole = String(paddedDigits[..<splitIndex])
        var fractional = String(paddedDigits[splitIndex...])
        while fractional.last == "0" {
            fractional.removeLast()
        }
        return fractional.isEmpty ? whole : "\(whole).\(fractional)"
    }

    static func solAmount(_ lamports: UInt64) -> String {
        let sol = Decimal(lamports) / Decimal(lamportsPerSOL)
        return "\(sol.formatted(.number.precision(.fractionLength(0 ... 9)))) SOL"
    }
}
