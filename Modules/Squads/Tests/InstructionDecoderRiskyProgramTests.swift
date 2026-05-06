import Testing
@testable import Squads

struct SystemAdminInstructionDecoderTests {
    private let decoder = InstructionDecoder()

    @Test func decodesNonceCreationAndSystemAdminActions() {
        let zeroPubkeyHex = String(repeating: "00", count: 32)
        let createNonce = SquadDecodedInstruction(
            program: "11111111111111111111111111111111",
            kind: "raw",
            summary: "",
            rawDataHex: "0000000040420f00000000005000000000000000\(zeroPubkeyHex)"
        )
        let initializeNonce = SquadDecodedInstruction(
            program: "11111111111111111111111111111111",
            kind: "raw",
            summary: "",
            rawDataHex: "06000000\(zeroPubkeyHex)"
        )
        let withdrawNonce = SquadDecodedInstruction(
            program: "11111111111111111111111111111111",
            kind: "raw",
            summary: "",
            rawDataHex: "0500000040420f0000000000"
        )
        let advanceNonce = SquadDecodedInstruction(
            program: "11111111111111111111111111111111",
            kind: "raw",
            summary: "",
            rawDataHex: "04000000"
        )

        let decodedCreate = decoder.decode(createNonce)
        let decodedInitialize = decoder.decode(initializeNonce)
        let decodedWithdraw = decoder.decode(withdrawNonce)
        let decodedAdvance = decoder.decode(advanceNonce)

        #expect(decodedCreate.kind == "create_nonce_account")
        #expect(decodedCreate.summary == "Create nonce account with 0.001 SOL")
        #expect(decodedInitialize.kind == "initialize_nonce_account")
        #expect(decodedInitialize.summary == "Initialize nonce authority 11111111111111111111111111111111")
        #expect(decodedWithdraw.kind == "withdraw_nonce_account")
        #expect(decodedWithdraw.summary == "Withdraw 0.001 SOL from nonce account")
        #expect(decodedAdvance.kind == "advance_nonce_account")
        #expect(decodedAdvance.summary == "Advance nonce")
    }
}

struct StakeAndLookupInstructionDecoderTests {
    private let decoder = InstructionDecoder()

    @Test func decodesStakeProgramActions() {
        let zeroPubkeyHex = String(repeating: "00", count: 32)
        let authorize = SquadDecodedInstruction(
            program: "Stake11111111111111111111111111111111111111",
            kind: "raw",
            summary: "",
            rawDataHex: "01000000\(zeroPubkeyHex)01000000"
        )
        let delegate = SquadDecodedInstruction(
            program: "Stake11111111111111111111111111111111111111",
            kind: "raw",
            summary: "",
            accounts: [
                "stake",
                "vote",
                "clock",
                "history",
                "config",
                "authority"
            ],
            rawDataHex: "02000000"
        )
        let withdraw = SquadDecodedInstruction(
            program: "Stake11111111111111111111111111111111111111",
            kind: "raw",
            summary: "",
            rawDataHex: "0400000040420f0000000000"
        )

        let decodedAuthorize = decoder.decode(authorize)
        let decodedDelegate = decoder.decode(delegate)
        let decodedWithdraw = decoder.decode(withdraw)

        #expect(decodedAuthorize.programLabel == "Stake Program")
        #expect(decodedAuthorize.kind == "stake_authority_change")
        #expect(decodedAuthorize.summary == "Set stake withdraw authority to 11111111111111111111111111111111")
        #expect(decodedDelegate.kind == "stake_delegate")
        #expect(decodedDelegate.summary == "Delegate stake to vote")
        #expect(decodedWithdraw.kind == "stake_withdraw")
        #expect(decodedWithdraw.summary == "Withdraw 0.001 SOL from stake")
    }

    @Test func decodesAddressLookupTableActions() {
        let zeroPubkeyHex = String(repeating: "00", count: 32)
        let create = SquadDecodedInstruction(
            program: "AddressLookupTab1e1111111111111111111111111",
            kind: "raw",
            summary: "",
            rawDataHex: "000000002a00000000000000ff"
        )
        let extend = SquadDecodedInstruction(
            program: "AddressLookupTab1e1111111111111111111111111",
            kind: "raw",
            summary: "",
            rawDataHex: "020000000100000000000000\(zeroPubkeyHex)"
        )
        let close = SquadDecodedInstruction(
            program: "AddressLookupTab1e1111111111111111111111111",
            kind: "raw",
            summary: "",
            rawDataHex: "04000000"
        )

        let decodedCreate = decoder.decode(create)
        let decodedExtend = decoder.decode(extend)
        let decodedClose = decoder.decode(close)

        #expect(decodedCreate.programLabel == "Address Lookup Table Program")
        #expect(decodedCreate.kind == "lookup_table_create")
        #expect(decodedCreate.summary == "Create address lookup table using recent slot 42")
        #expect(decodedExtend.kind == "lookup_table_extend")
        #expect(decodedExtend.summary == "Extend address lookup table with 1 address")
        #expect(decodedClose.kind == "lookup_table_close")
        #expect(decodedClose.summary == "Close address lookup table")
    }
}
