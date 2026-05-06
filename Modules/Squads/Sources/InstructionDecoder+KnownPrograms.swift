import Foundation

extension InstructionDecoder {
    static let associatedTokenAccountProgramID = "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL"
    static let memoProgramID = "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr"
    static let memoLegacyProgramID = "Memo1UhkJRfHyvLMcVucJwxXeuD728EqVDDwQDxFMNo"
    static let computeBudgetProgramID = "ComputeBudget111111111111111111111111111111"

    func decodeAssociatedTokenAccountInstruction(
        _ instruction: SquadDecodedInstruction,
        data: [UInt8],
        accounts: [String]
    ) -> DecodedInstructionDisplay {
        let kind: String
        let summary: String

        switch data.first {
        case nil, .some(0):
            kind = "create"
            summary = "Create associated token account"
        case .some(1):
            kind = "create_idempotent"
            summary = "Create associated token account if needed"
        case .some(2):
            kind = "recover_nested"
            summary = "Recover nested associated token account"
        default:
            return fallback(instruction, accounts: accounts)
        }

        return DecodedInstructionDisplay(
            programLabel: "Associated Token Account Program",
            kind: kind,
            summary: summary,
            accounts: accounts,
            dataHex: instruction.rawDataHex
        )
    }

    func decodeMemoInstruction(
        _ instruction: SquadDecodedInstruction,
        data: [UInt8],
        accounts: [String]
    ) -> DecodedInstructionDisplay {
        guard let decodedMemo = String(bytes: data, encoding: .utf8) else {
            return fallback(instruction, accounts: accounts)
        }

        let memo = decodedMemo.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = memo.isEmpty ? "Memo" : "Memo: \(Self.shortText(memo, maxCharacters: 80))"
        return DecodedInstructionDisplay(
            programLabel: "Memo Program",
            kind: "memo",
            summary: summary,
            accounts: accounts,
            dataHex: instruction.rawDataHex
        )
    }

    func decodeComputeBudgetInstruction(
        _ instruction: SquadDecodedInstruction,
        data: [UInt8],
        accounts: [String]
    ) -> DecodedInstructionDisplay {
        guard let discriminator = data.first else {
            return fallback(instruction, accounts: accounts)
        }

        let kind: String
        let summary: String

        switch discriminator {
        case 0:
            guard let units = Self.uint32(data, at: 1), let additionalFee = Self.uint32(data, at: 5) else {
                return fallback(instruction, accounts: accounts)
            }
            kind = "request_units_deprecated"
            summary = "Request \(units) compute units with \(additionalFee) additional fee"
        case 1:
            guard let bytes = Self.uint32(data, at: 1) else {
                return fallback(instruction, accounts: accounts)
            }
            kind = "request_heap_frame"
            summary = "Request \(bytes) byte heap frame"
        case 2:
            guard let units = Self.uint32(data, at: 1) else {
                return fallback(instruction, accounts: accounts)
            }
            kind = "set_compute_unit_limit"
            summary = "Set compute unit limit to \(units)"
        case 3:
            guard let microLamports = Self.uint64(data, at: 1) else {
                return fallback(instruction, accounts: accounts)
            }
            kind = "set_compute_unit_price"
            summary = "Set compute unit price to \(microLamports) micro-lamports"
        default:
            return fallback(instruction, accounts: accounts)
        }

        return DecodedInstructionDisplay(
            programLabel: "Compute Budget Program",
            kind: kind,
            summary: summary,
            accounts: accounts,
            dataHex: instruction.rawDataHex
        )
    }

    static func isAssociatedTokenAccountProgram(_ program: String) -> Bool {
        program == associatedTokenAccountProgramID || program == "Associated Token Account Program"
    }

    static func isMemoProgram(_ program: String) -> Bool {
        program == memoProgramID || program == memoLegacyProgramID || program == "Memo Program"
    }

    static func isComputeBudgetProgram(_ program: String) -> Bool {
        program == computeBudgetProgramID || program == "Compute Budget Program"
    }

    static func shortText(_ value: String, maxCharacters: Int) -> String {
        guard value.count > maxCharacters else {
            return value
        }
        return "\(value.prefix(maxCharacters))..."
    }
}
