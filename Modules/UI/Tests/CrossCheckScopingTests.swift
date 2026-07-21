import Foundation
import Indexer
import Squads
import Testing
@testable import UI

/// Guards the fail-safe scoping of the tier-3 effect cross-check. The relay reports
/// transaction-wide effects with no per-instruction attribution, so an aggregate simulation
/// leg can confirm the wrong instruction in a multi-instruction proposal. These tests pin the
/// same effects/instruction/spec and flip only the instruction count, proving the count guard
/// is what closes the false Confirm.
struct CrossCheckScopingTests {
    private let program = "SPoo1Ku8WFXoNDMHPsrGSTSG1Y47rzgn41SLUNakuHy"
    private let vault = "vaultAddr"

    private func stakeSpec() throws -> DecodeSpec {
        try JSONDecoder().decode(DecodeSpec.self, from: Data(#"""
        { "program":"\#(program)","discriminator":[14],"mode":"standalone",
          "layout":[{"name":"lamports","type":"u64"}],"action":"Stake","accounts":{"vault":0},
          "template":"Stake {lamports:sol}",
          "effects":[{"direction":"out","asset":"SOL","amount":"arg(lamports)"}] }
        """#.utf8))
    }

    /// Declares "Stake 50 SOL".
    private var stakeFiftyInstruction: SquadDecodedInstruction {
        SquadDecodedInstruction(
            program: program, kind: "raw", summary: "",
            accounts: [vault], rawDataHex: "0e" + lamportsLEHex(50_000_000_000)
        )
    }

    /// Transaction-wide simulation: the vault sends 30 SOL (this instruction's real move) and a
    /// separate 50 SOL leg (a sibling instruction). Under an aggregate cross-check, the 50-SOL leg
    /// would falsely confirm the "Stake 50 SOL" statement.
    private var aggregateEffects: [RelayInspectionEffect] {
        [
            effect(amount: "30"),
            effect(amount: "50")
        ]
    }

    private func effect(amount: String) -> RelayInspectionEffect {
        RelayInspectionEffect(
            kind: "transfer", summary: "", program: nil,
            asset: "SOL", amount: amount, source: vault, destination: "stakePool"
        )
    }

    @Test func multiInstructionProposalBuildsNoContext() {
        let context = proposalCrossCheckContext(
            instructionCount: 2, effects: aggregateEffects,
            ownVaultAccounts: [vault], resolvedMints: [:]
        )
        #expect(context == nil)
    }

    @Test func multiInstructionRegistryDecodeDoesNotFalselyConfirm() throws {
        let context = proposalCrossCheckContext(
            instructionCount: 2, effects: aggregateEffects,
            ownVaultAccounts: [vault], resolvedMints: [:]
        )
        let decoded = try InstructionDecoder().decode(
            stakeFiftyInstruction, accounts: [vault],
            specs: [program: [stakeSpec()]], crossCheck: context
        )
        // Registry decode still shows shape, but the aggregate simulation cannot confirm it.
        #expect(decoded.kind == "Stake")
        #expect(decoded.crossCheck == nil)
        #expect(registryConfidence(provenance: decoded.provenance, crossCheck: decoded.crossCheck) == .idl)
    }

    @Test func singleInstructionStillConfirmsSameEffects() throws {
        let context = proposalCrossCheckContext(
            instructionCount: 1, effects: aggregateEffects,
            ownVaultAccounts: [vault], resolvedMints: [:]
        )
        #expect(context != nil)
        let decoded = try InstructionDecoder().decode(
            stakeFiftyInstruction, accounts: [vault],
            specs: [program: [stakeSpec()]], crossCheck: context
        )
        #expect(decoded.crossCheck == .confirmed)
        #expect(registryConfidence(provenance: decoded.provenance, crossCheck: decoded.crossCheck) == .known)
    }

    @Test func singleInstructionContradictionStillSurfaces() throws {
        let context = proposalCrossCheckContext(
            instructionCount: 1, effects: [effect(amount: "30")],
            ownVaultAccounts: [vault], resolvedMints: [:]
        )
        let decoded = try InstructionDecoder().decode(
            stakeFiftyInstruction, accounts: [vault],
            specs: [program: [stakeSpec()]], crossCheck: context
        )
        #expect(decoded.crossCheck == .contradicted)
        #expect(registryConfidence(provenance: decoded.provenance, crossCheck: decoded.crossCheck) == nil)
    }
}

private func lamportsLEHex(_ value: UInt64) -> String {
    (0 ..< 8).map { String(format: "%02x", UInt8((value >> ($0 * 8)) & 0xFF)) }.joined()
}
