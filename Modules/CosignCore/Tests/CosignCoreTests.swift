import Testing
@testable import CosignCore

struct CosignCoreTests {
    @Test func validatesSolanaPubkeys() {
        #expect(CosignCore.isValidSolanaPubkey("11111111111111111111111111111111"))
        #expect(!CosignCore.isValidSolanaPubkey(""))
        #expect(!CosignCore.isValidSolanaPubkey("not-a-solana-address"))
        #expect(!CosignCore.isValidSolanaPubkey("00000000000000000000000000000000"))
    }

    @Test func derivesAssociatedTokenAccountAddress() throws {
        let address = try CosignCore.deriveAssociatedTokenAccountAddress(
            owner: "11111111111111111111111111111111",
            mint: "So11111111111111111111111111111111111111112",
            tokenProgramID: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
        )

        #expect(CosignCore.isValidSolanaPubkey(address))
    }

    @Test func decodeProposalDecodesASystemTransfer() async {
        // Empty relayBaseUrl ⇒ no augmentation fetch ⇒ tier-1 primitive decode
        // only. Exercises the full FFI round trip incl. the DecodeProvenance
        // enum and the async bridge.
        let request = DecodeProposalRequest(
            relayBaseUrl: "",
            relayCapabilities: [],
            instructions: [
                DecodedInstruction(
                    program: "11111111111111111111111111111111",
                    kind: "raw",
                    summary: "",
                    accounts: ["from", "to"],
                    rawDataHex: "020000008813000000000000",
                    configAction: nil
                )
            ],
            accountsReferenced: ["from", "to"],
            ownVaultAccounts: [],
            inspectionEffects: [],
            lastAcceptedManifestIssuedAt: nil
        )
        let result = await CosignCore.decodeProposal(request)
        #expect(result.instructions.count == 1)
        #expect(result.instructions[0].programLabel == "System Program")
        #expect(result.instructions[0].summary == "Transfer 0.000005 SOL")
        #expect(result.hasContradiction == false)
        #expect(result.instructions[0].crossCheck == nil)
    }

    @Test func decodeProposalRoundTripsManifestIssuedAt() async {
        // The last-accepted manifest issuedAt threads in on the request and the
        // accepted issuedAt threads back out on the result. With an empty relay
        // (no manifest fetched) and the shipped empty pinned-root set, no
        // manifest verifies, so nothing is accepted: the field round-trips as
        // nil — tier-3 stays inert exactly as today.
        let request = DecodeProposalRequest(
            relayBaseUrl: "",
            relayCapabilities: [],
            instructions: [
                DecodedInstruction(
                    program: "11111111111111111111111111111111",
                    kind: "raw",
                    summary: "",
                    accounts: ["from", "to"],
                    rawDataHex: "020000008813000000000000",
                    configAction: nil
                )
            ],
            accountsReferenced: ["from", "to"],
            ownVaultAccounts: [],
            inspectionEffects: [],
            lastAcceptedManifestIssuedAt: nil
        )
        #expect(request.lastAcceptedManifestIssuedAt == nil)
        let result = await CosignCore.decodeProposal(request)
        #expect(result.acceptedManifestIssuedAt == nil)
        #expect(result.instructions.count == 1)
    }

    // Ported from the deleted `CrossCheckScopingTests` (Modules/UI/Tests), which
    // exercised the single-instruction cross-check gate through the now-removed
    // Swift `proposalCrossCheckContext`/`InstructionDecoder`. That gate
    // (`build_cross_check` in Rust) is unit-tested directly in `core/src/decode/mod.rs`;
    // these two scenarios assert its FFI-visible, key-independent behavior — the
    // wiring compiles and the multi-instruction/no-effects paths never surface a
    // verdict, regardless of registry population (`relayBaseUrl: ""` fetches no
    // augmentation, so specs are always empty here).

    @Test func multiInstructionProposalBuildsNoCrossCheck() async {
        // Transaction-wide simulation effects can't be attributed to a single
        // instruction once there's more than one in the proposal, so the gate
        // must not attach a verdict to either instruction.
        let transfer = DecodedInstruction(
            program: "11111111111111111111111111111111",
            kind: "raw",
            summary: "",
            accounts: ["from", "to"],
            rawDataHex: "020000008813000000000000",
            configAction: nil
        )
        let request = DecodeProposalRequest(
            relayBaseUrl: "",
            relayCapabilities: [],
            instructions: [transfer, transfer],
            accountsReferenced: ["from", "to"],
            ownVaultAccounts: ["from"],
            inspectionEffects: [
                RelayInspectionEffect(
                    kind: "transfer", summary: "", program: nil,
                    asset: "SOL", amount: "0.000005", source: "from", destination: "to"
                )
            ],
            lastAcceptedManifestIssuedAt: nil
        )
        let result = await CosignCore.decodeProposal(request)
        #expect(result.instructions.count == 2)
        #expect(result.instructions[0].crossCheck == nil)
        #expect(result.instructions[1].crossCheck == nil)
        #expect(result.hasContradiction == false)
    }

    @Test func singleInstructionWithNoEffectsBuildsNoCrossCheck() async {
        // A single-instruction proposal with no inspection effects (e.g. the
        // relay reported nothing, or inspection hasn't loaded yet) must not
        // fabricate a verdict either.
        let request = DecodeProposalRequest(
            relayBaseUrl: "",
            relayCapabilities: [],
            instructions: [
                DecodedInstruction(
                    program: "11111111111111111111111111111111",
                    kind: "raw",
                    summary: "",
                    accounts: ["from", "to"],
                    rawDataHex: "020000008813000000000000",
                    configAction: nil
                )
            ],
            accountsReferenced: ["from", "to"],
            ownVaultAccounts: ["from"],
            inspectionEffects: [],
            lastAcceptedManifestIssuedAt: nil
        )
        let result = await CosignCore.decodeProposal(request)
        #expect(result.instructions.count == 1)
        #expect(result.instructions[0].crossCheck == nil)
        #expect(result.hasContradiction == false)
    }
}
