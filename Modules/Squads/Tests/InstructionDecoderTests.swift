import Testing
@testable import Squads

struct InstructionDecoderTests {
    private let decoder = InstructionDecoder()

    @Test func decodesSystemTransfer() {
        let instruction = SquadDecodedInstruction(
            program: "11111111111111111111111111111111",
            kind: "raw",
            summary: "",
            rawDataHex: "020000008813000000000000"
        )

        let decoded = decoder.decode(instruction, accounts: ["from", "to"])

        #expect(decoded.programLabel == "System Program")
        #expect(decoded.kind == "transfer")
        #expect(decoded.summary == "Transfer 0.000005 SOL")
        #expect(decoded.accounts == ["from", "to"])
    }

    @Test func decodesSystemCreateAccount() {
        let instruction = SquadDecodedInstruction(
            program: "11111111111111111111111111111111",
            kind: "raw",
            summary: "",
            rawDataHex: "000000002a00000000000000a50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
        )

        let decoded = decoder.decode(instruction)

        #expect(decoded.programLabel == "System Program")
        #expect(decoded.kind == "create_account")
        #expect(
            decoded.summary ==
                "Create account with 0.000000042 SOL, 165 bytes, owner 11111111111111111111111111111111"
        )
    }

    @Test func decodesSystemOwnerAndNonceAuthorityChanges() {
        let zeroPubkeyHex = String(repeating: "00", count: 32)
        let assign = SquadDecodedInstruction(
            program: "11111111111111111111111111111111",
            kind: "raw",
            summary: "",
            rawDataHex: "01000000\(zeroPubkeyHex)"
        )
        let nonce = SquadDecodedInstruction(
            program: "11111111111111111111111111111111",
            kind: "raw",
            summary: "",
            rawDataHex: "07000000\(zeroPubkeyHex)"
        )

        let decodedAssign = decoder.decode(assign, accounts: ["account"])
        let decodedNonce = decoder.decode(nonce, accounts: ["nonce", "authority"])

        #expect(decodedAssign.kind == "assign")
        #expect(decodedAssign.summary == "Assign account owner to 11111111111111111111111111111111")
        #expect(decodedNonce.kind == "authorize_nonce_account")
        #expect(decodedNonce.summary == "Authorize nonce authority 11111111111111111111111111111111")
    }

    @Test func decodesAssociatedTokenAccountCreate() {
        let instruction = SquadDecodedInstruction(
            program: "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL",
            kind: "raw",
            summary: "",
            accounts: [
                "payer",
                "associated-token-account",
                "wallet",
                "mint"
            ],
            rawDataHex: ""
        )

        let decoded = decoder.decode(instruction)

        #expect(decoded.programLabel == "Associated Token Account Program")
        #expect(decoded.kind == "create")
        #expect(decoded.summary == "Create associated token account")
        #expect(decoded.accounts == ["payer", "associated-token-account", "wallet", "mint"])
    }

    @Test func decodesAssociatedTokenAccountCreateIdempotent() {
        let instruction = SquadDecodedInstruction(
            program: "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL",
            kind: "raw",
            summary: "",
            rawDataHex: "01"
        )

        let decoded = decoder.decode(instruction)

        #expect(decoded.programLabel == "Associated Token Account Program")
        #expect(decoded.kind == "create_idempotent")
        #expect(decoded.summary == "Create associated token account if needed")
    }

    @Test func decodesMemoInstruction() {
        let instruction = SquadDecodedInstruction(
            program: "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr",
            kind: "raw",
            summary: "",
            rawDataHex: "68656c6c6f"
        )

        let decoded = decoder.decode(instruction)

        #expect(decoded.programLabel == "Memo Program")
        #expect(decoded.kind == "memo")
        #expect(decoded.summary == "Memo: hello")
    }

    @Test func decodesComputeBudgetInstruction() {
        let instruction = SquadDecodedInstruction(
            program: "ComputeBudget111111111111111111111111111111",
            kind: "raw",
            summary: "",
            rawDataHex: "02a0860100"
        )

        let decoded = decoder.decode(instruction)

        #expect(decoded.programLabel == "Compute Budget Program")
        #expect(decoded.kind == "set_compute_unit_limit")
        #expect(decoded.summary == "Set compute unit limit to 100000")
    }

    @Test func decodesUpgradeableLoaderProgramAdminActions() {
        let upgrade = SquadDecodedInstruction(
            program: "BPFLoaderUpgradeab1e11111111111111111111111",
            kind: "raw",
            summary: "",
            accounts: [
                "program-data",
                "program",
                "buffer",
                "spill",
                "rent",
                "clock",
                "authority"
            ],
            rawDataHex: "03000000"
        )
        let setAuthority = SquadDecodedInstruction(
            program: "BPFLoaderUpgradeab1e11111111111111111111111",
            kind: "raw",
            summary: "",
            accounts: [
                "program-data",
                "authority",
                "new-authority"
            ],
            rawDataHex: "04000000"
        )

        let decodedUpgrade = decoder.decode(upgrade)
        let decodedSetAuthority = decoder.decode(setAuthority)

        #expect(decodedUpgrade.programLabel == "BPF Upgradeable Loader")
        #expect(decodedUpgrade.kind == "program_upgrade")
        #expect(decodedUpgrade.summary == "Upgrade program program")
        #expect(decodedSetAuthority.kind == "program_upgrade_authority_change")
        #expect(decodedSetAuthority.summary == "Set upgrade authority to new-authority")
    }

    @Test func passesThroughSquadsConfigSummary() {
        let instruction = SquadDecodedInstruction(
            program: "Squads",
            kind: "change_threshold",
            summary: "Change threshold to 3",
            rawDataHex: ""
        )

        let decoded = decoder.decode(instruction, accounts: ["member-a"])

        #expect(decoded.programLabel == "Squads")
        #expect(decoded.kind == "change_threshold")
        #expect(decoded.summary == "Change threshold to 3")
        #expect(decoded.accounts == ["member-a"])
    }

    @Test func fallsBackForUnknownPrograms() {
        let instruction = SquadDecodedInstruction(
            program: "Unknown111111111111111111111111111111111",
            kind: "raw",
            summary: "",
            rawDataHex: "ff"
        )

        let decoded = decoder.decode(instruction)

        #expect(decoded.programLabel == "Unknown111111111111111111111111111111111")
        #expect(decoded.kind == "raw")
        #expect(decoded.summary == "Instruction for Unknown111111111111111111111111111111111")
        #expect(decoded.dataHex == "ff")
    }

    @Test func decodesProposalWithSharedReferencedAccounts() {
        let proposal = SquadProposalDetail(
            transactionIndex: 7,
            status: "Active",
            votesYes: 1,
            votesNo: 0,
            votesCancelled: 0,
            threshold: 2,
            kind: "vault",
            votersYes: [],
            votersNo: [],
            votersCancelled: [],
            instructions: [
                SquadDecodedInstruction(
                    program: "11111111111111111111111111111111",
                    kind: "raw",
                    summary: "",
                    rawDataHex: "020000000100000000000000"
                )
            ],
            accountsReferenced: ["from", "to"],
            transactionAddress: nil
        )

        let decoded = decoder.decode(proposal)

        #expect(decoded.count == 1)
        #expect(decoded[0].accounts == ["from", "to"])
        #expect(decoded[0].summary == "Transfer 0.000000001 SOL")
    }
}

struct TokenInstructionDecoderTests {
    private let decoder = InstructionDecoder()

    @Test func decodesSPLTokenTransfer() {
        let instruction = SquadDecodedInstruction(
            program: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
            kind: "raw",
            summary: "",
            accounts: [
                "source-token-account",
                "destination-token-account",
                "owner"
            ],
            rawDataHex: "03e803000000000000"
        )

        let decoded = decoder.decode(instruction)

        #expect(decoded.programLabel == "SPL Token Program")
        #expect(decoded.kind == "transfer")
        #expect(decoded.summary == "Transfer 1000 base units to destin...ccount")
        #expect(decoded.accounts == ["source-token-account", "destination-token-account", "owner"])
    }

    @Test func decodesSPLTokenTransferChecked() {
        let instruction = SquadDecodedInstruction(
            program: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
            kind: "raw",
            summary: "",
            accounts: [
                "source-token-account",
                "mint",
                "recipient-token-account",
                "owner"
            ],
            rawDataHex: "0c44d612000000000006"
        )

        let decoded = decoder.decode(instruction)

        #expect(decoded.kind == "transfer_checked")
        #expect(decoded.summary == "Transfer 1.2345 tokens to recipi...ccount")
    }

    @Test func decodesToken2022TransferChecked() {
        let instruction = SquadDecodedInstruction(
            program: "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb",
            kind: "raw",
            summary: "",
            accounts: [
                "source-token-account",
                "mint",
                "recipient-token-account",
                "owner"
            ],
            rawDataHex: "0c40420f000000000006"
        )

        let decoded = decoder.decode(instruction)

        #expect(decoded.programLabel == "Token-2022 Program")
        #expect(decoded.kind == "transfer_checked")
        #expect(decoded.summary == "Transfer 1 tokens to recipi...ccount")
    }

    @Test func decodesTokenDelegateAndAuthorityChanges() {
        let zeroPubkeyHex = String(repeating: "00", count: 32)
        let approve = SquadDecodedInstruction(
            program: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
            kind: "raw",
            summary: "",
            accounts: ["source", "delegate", "owner"],
            rawDataHex: "04e803000000000000"
        )
        let setAuthority = SquadDecodedInstruction(
            program: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
            kind: "raw",
            summary: "",
            rawDataHex: "060001000000\(zeroPubkeyHex)"
        )
        let clearAuthority = SquadDecodedInstruction(
            program: "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb",
            kind: "raw",
            summary: "",
            rawDataHex: "060300000000"
        )

        let decodedApprove = decoder.decode(approve)
        let decodedSetAuthority = decoder.decode(setAuthority)
        let decodedClearAuthority = decoder.decode(clearAuthority)

        #expect(decodedApprove.kind == "approve")
        #expect(decodedApprove.summary == "Approve 1000 base units for delegate")
        #expect(decodedSetAuthority.kind == "set_authority")
        #expect(decodedSetAuthority.summary == "Set token mint authority to 11111111111111111111111111111111")
        #expect(decodedClearAuthority.programLabel == "Token-2022 Program")
        #expect(decodedClearAuthority.summary == "Clear token close authority")
    }

    @Test func decodesTokenMintBurnAndAccountControls() {
        let mint = SquadDecodedInstruction(
            program: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
            kind: "raw",
            summary: "",
            accounts: ["mint", "destination", "authority"],
            rawDataHex: "0e40420f000000000006"
        )
        let burn = SquadDecodedInstruction(
            program: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
            kind: "raw",
            summary: "",
            accounts: ["source", "mint", "authority"],
            rawDataHex: "0f40420f000000000006"
        )
        let close = SquadDecodedInstruction(
            program: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
            kind: "raw",
            summary: "",
            accounts: ["token-account", "destination", "owner"],
            rawDataHex: "09"
        )
        let freeze = SquadDecodedInstruction(
            program: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
            kind: "raw",
            summary: "",
            accounts: ["token-account", "mint", "authority"],
            rawDataHex: "0a"
        )

        let decodedMint = decoder.decode(mint)
        let decodedBurn = decoder.decode(burn)
        let decodedClose = decoder.decode(close)
        let decodedFreeze = decoder.decode(freeze)

        #expect(decodedMint.kind == "mint_to_checked")
        #expect(decodedMint.summary == "Mint 1 tokens to destination")
        #expect(decodedBurn.kind == "burn_checked")
        #expect(decodedBurn.summary == "Burn 1 tokens from source")
        #expect(decodedClose.kind == "close_account")
        #expect(decodedClose.summary == "Close token account token-account")
        #expect(decodedFreeze.kind == "freeze_account")
        #expect(decodedFreeze.summary == "Freeze token account token-account")
    }

    @Test func decodesTokenMintInitialization() {
        let zeroPubkeyHex = String(repeating: "00", count: 32)
        let instruction = SquadDecodedInstruction(
            program: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
            kind: "raw",
            summary: "",
            rawDataHex: "0006\(zeroPubkeyHex)00000000"
        )

        let decoded = decoder.decode(instruction)

        #expect(decoded.kind == "initialize_mint")
        #expect(
            decoded.summary ==
                "Initialize mint with 6 decimals, mint authority 11111111111111111111111111111111, no freeze authority"
        )
    }
}
