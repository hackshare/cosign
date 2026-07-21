import Testing
@testable import Squads

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
