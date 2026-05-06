import CosignCore
import Foundation

extension InstructionDecoder {
    static let bpfUpgradeableLoaderProgramID = "BPFLoaderUpgradeab1e11111111111111111111111"
    static let nonceAccountDataLength: UInt64 = 80

    func decodeSystemInstruction(
        _ instruction: SquadDecodedInstruction,
        data: [UInt8],
        accounts: [String]
    ) -> DecodedInstructionDisplay {
        guard let discriminator = Self.uint32(data, at: 0) else {
            return fallback(instruction, accounts: accounts)
        }

        if let decoded = decodeCoreSystemInstruction(
            discriminator,
            instruction: instruction,
            data: data,
            accounts: accounts
        ) {
            return decoded
        }
        if let decoded = decodeNonceSystemInstruction(
            discriminator,
            instruction: instruction,
            data: data,
            accounts: accounts
        ) {
            return decoded
        }
        if let decoded = decodeSeededSystemInstruction(
            discriminator,
            instruction: instruction,
            data: data,
            accounts: accounts
        ) {
            return decoded
        }
        return fallback(instruction, accounts: accounts)
    }

    func decodeCoreSystemInstruction(
        _ discriminator: UInt32,
        instruction: SquadDecodedInstruction,
        data: [UInt8],
        accounts: [String]
    ) -> DecodedInstructionDisplay? {
        switch discriminator {
        case 0:
            decodeCreateAccount(instruction, data: data, accounts: accounts)
        case 1:
            decodeAssign(instruction, data: data, accounts: accounts)
        case 2:
            decodeSystemTransfer(instruction, data: data, accounts: accounts)
        case 10:
            decodeAssignWithSeed(instruction, data: data, accounts: accounts)
        default:
            nil
        }
    }

    func decodeNonceSystemInstruction(
        _ discriminator: UInt32,
        instruction: SquadDecodedInstruction,
        data: [UInt8],
        accounts: [String]
    ) -> DecodedInstructionDisplay? {
        switch discriminator {
        case 4:
            systemDisplay(instruction, kind: "advance_nonce_account", summary: "Advance nonce", accounts: accounts)
        case 5:
            decodeWithdrawNonce(instruction, data: data, accounts: accounts)
        case 6:
            decodeNonceAuthorityChange(
                instruction,
                data: data,
                accounts: accounts,
                kind: "initialize_nonce_account",
                summaryPrefix: "Initialize nonce authority"
            )
        case 7:
            decodeNonceAuthorityChange(
                instruction,
                data: data,
                accounts: accounts,
                kind: "authorize_nonce_account",
                summaryPrefix: "Authorize nonce authority"
            )
        case 12:
            systemDisplay(
                instruction,
                kind: "upgrade_nonce_account",
                summary: "Upgrade nonce account",
                accounts: accounts
            )
        default:
            nil
        }
    }

    func decodeSeededSystemInstruction(
        _ discriminator: UInt32,
        instruction: SquadDecodedInstruction,
        data: [UInt8],
        accounts: [String]
    ) -> DecodedInstructionDisplay? {
        switch discriminator {
        case 3:
            decodeCreateAccountWithSeed(instruction, data: data, accounts: accounts)
        case 8:
            decodeAllocate(instruction, data: data, accounts: accounts, kind: "allocate", summaryPrefix: "Allocate")
        case 9:
            decodeAllocateWithSeed(instruction, data: data, accounts: accounts)
        case 11:
            decodeTransferWithSeed(instruction, data: data, accounts: accounts)
        default:
            nil
        }
    }

    func decodeUpgradeableLoaderInstruction(
        _ instruction: SquadDecodedInstruction,
        data: [UInt8],
        accounts: [String]
    ) -> DecodedInstructionDisplay {
        guard let metadata = Self.upgradeableLoaderMetadata(data: data, accounts: accounts) else {
            return fallback(instruction, accounts: accounts)
        }

        return upgradeableLoaderDisplay(
            instruction,
            kind: metadata.kind,
            summary: metadata.summary,
            accounts: accounts
        )
    }

    static func upgradeableLoaderMetadata(
        data: [UInt8],
        accounts: [String]
    ) -> (kind: String, summary: String)? {
        guard let discriminator = data.first else {
            return nil
        }

        switch discriminator {
        case 0:
            return ("program_buffer_initialize", "Initialize program buffer")
        case 1:
            return programBufferWriteMetadata(data: data)
        case 2:
            return (
                "program_deploy",
                programAdminSummary("Deploy upgradeable program", address: account(at: 2, in: accounts))
            )
        case 3:
            return ("program_upgrade", programAdminSummary("Upgrade program", address: account(at: 1, in: accounts)))
        case 4:
            return ("program_upgrade_authority_change", upgradeAuthoritySummary(accounts: accounts, checked: false))
        case 5:
            return ("program_close", "Close upgradeable loader account")
        case 6:
            return ("program_extend", programExtendSummary(data: data))
        case 7:
            return ("program_upgrade_authority_change", upgradeAuthoritySummary(accounts: accounts, checked: true))
        default:
            return nil
        }
    }

    func decodeCreateAccount(
        _ instruction: SquadDecodedInstruction,
        data: [UInt8],
        accounts: [String]
    ) -> DecodedInstructionDisplay {
        guard
            let lamports = Self.uint64(data, at: 4),
            let space = Self.uint64(data, at: 12),
            let owner = Self.pubkey(data, at: 20)
        else {
            return fallback(instruction, accounts: accounts)
        }

        let isNonce = Self.isNonceAccountCreation(space: space, owner: owner)
        return systemDisplay(
            instruction,
            kind: isNonce ? "create_nonce_account" : "create_account",
            summary: isNonce
                ? "Create nonce account with \(Self.solAmount(lamports))"
                : "Create account with \(Self.solAmount(lamports)), \(space) bytes, owner \(owner)",
            accounts: accounts
        )
    }

    func decodeAssign(
        _ instruction: SquadDecodedInstruction,
        data: [UInt8],
        accounts: [String]
    ) -> DecodedInstructionDisplay {
        guard let owner = Self.pubkey(data, at: 4) else {
            return fallback(instruction, accounts: accounts)
        }

        return systemDisplay(
            instruction,
            kind: "assign",
            summary: "Assign account owner to \(owner)",
            accounts: accounts
        )
    }

    func decodeSystemTransfer(
        _ instruction: SquadDecodedInstruction,
        data: [UInt8],
        accounts: [String]
    ) -> DecodedInstructionDisplay {
        guard let lamports = Self.uint64(data, at: 4) else {
            return fallback(instruction, accounts: accounts)
        }

        return systemDisplay(
            instruction,
            kind: "transfer",
            summary: "Transfer \(Self.solAmount(lamports))",
            accounts: accounts
        )
    }

    func decodeNonceAuthorityChange(
        _ instruction: SquadDecodedInstruction,
        data: [UInt8],
        accounts: [String],
        kind: String,
        summaryPrefix: String
    ) -> DecodedInstructionDisplay {
        guard let authority = Self.pubkey(data, at: 4) else {
            return fallback(instruction, accounts: accounts)
        }

        return systemDisplay(
            instruction,
            kind: kind,
            summary: "\(summaryPrefix) \(authority)",
            accounts: accounts
        )
    }

    func decodeAssignWithSeed(
        _ instruction: SquadDecodedInstruction,
        data: [UInt8],
        accounts: [String]
    ) -> DecodedInstructionDisplay {
        guard
            let seed = Self.bincodeString(data, at: 36),
            let owner = Self.pubkey(data, at: seed.nextOffset)
        else {
            return fallback(instruction, accounts: accounts)
        }

        return systemDisplay(
            instruction,
            kind: "assign_with_seed",
            summary: "Assign seeded account owner to \(owner)",
            accounts: accounts
        )
    }

    static func programBufferWriteMetadata(data: [UInt8]) -> (kind: String, summary: String)? {
        guard let offset = uint32(data, at: 4) else {
            return nil
        }

        return ("program_buffer_write", "Write program buffer at offset \(offset)")
    }

    func systemDisplay(
        _ instruction: SquadDecodedInstruction,
        kind: String,
        summary: String,
        accounts: [String]
    ) -> DecodedInstructionDisplay {
        DecodedInstructionDisplay(
            programLabel: "System Program",
            kind: kind,
            summary: summary,
            accounts: accounts,
            dataHex: instruction.rawDataHex
        )
    }

    func upgradeableLoaderDisplay(
        _ instruction: SquadDecodedInstruction,
        kind: String,
        summary: String,
        accounts: [String]
    ) -> DecodedInstructionDisplay {
        DecodedInstructionDisplay(
            programLabel: "BPF Upgradeable Loader",
            kind: kind,
            summary: summary,
            accounts: accounts,
            dataHex: instruction.rawDataHex
        )
    }

    static func isSystemProgram(_ program: String) -> Bool {
        program == systemProgramID || program == "System Program"
    }

    static func isUpgradeableLoaderProgram(_ program: String) -> Bool {
        program == bpfUpgradeableLoaderProgramID || program == "BPF Upgradeable Loader" ||
            program == "bpf-upgradeable-loader"
    }

    static func isNonceAccountCreation(space: UInt64, owner: String) -> Bool {
        space == nonceAccountDataLength && owner == systemProgramID
    }

    static func programAdminSummary(_ prefix: String, address: String?) -> String {
        guard let address else {
            return prefix
        }
        return "\(prefix) \(address)"
    }

    static func upgradeAuthoritySummary(accounts: [String], checked: Bool) -> String {
        if let authority = account(at: 2, in: accounts) {
            return "Set upgrade authority to \(authority)"
        }

        return checked ? "Set upgrade authority" : "Clear upgrade authority"
    }

    static func programExtendSummary(data: [UInt8]) -> String {
        guard let additionalBytes = uint32(data, at: 4) else {
            return "Extend program"
        }
        return "Extend program by \(additionalBytes) bytes"
    }

    static func pubkey(_ bytes: [UInt8], at offset: Int) -> String? {
        guard bytes.count >= offset + 32 else {
            return nil
        }
        return CosignCore.base58(Data(bytes[offset ..< offset + 32]))
    }

    static func bincodeString(_ bytes: [UInt8], at offset: Int) -> (value: String, nextOffset: Int)? {
        guard let byteCount = uint64(bytes, at: offset), byteCount <= UInt64(Int.max) else {
            return nil
        }
        let count = Int(byteCount)
        let valueOffset = offset + 8
        guard bytes.count >= valueOffset + count else {
            return nil
        }
        let value = String(bytes: bytes[valueOffset ..< valueOffset + count], encoding: .utf8)
        return value.map { ($0, valueOffset + count) }
    }
}
