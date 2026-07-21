import Foundation
import Indexer
import Testing
@testable import Squads

struct InstructionDecoderCrossCheckTests {
    private let program = "SPoo1Ku8WFXoNDMHPsrGSTSG1Y47rzgn41SLUNakuHy"

    private func stakeSpec() throws -> DecodeSpec {
        try JSONDecoder().decode(DecodeSpec.self, from: Data(#"""
        { "program":"\#(program)","discriminator":[14],"mode":"standalone",
          "layout":[{"name":"lamports","type":"u64"}],"action":"Stake","accounts":{"vault":0},
          "template":"Stake {lamports:sol}",
          "effects":[{"direction":"out","asset":"SOL","amount":"arg(lamports)"}] }
        """#.utf8))
    }

    @Test func decodeCarriesVerdictThroughInterpretSpec() throws {
        let instruction = SquadDecodedInstruction(
            program: program,
            kind: "raw",
            summary: "",
            rawDataHex: "0e" + "0094357700000000"
        )
        let context = CrossCheckContext(
            simulated: AssetMovement(legs: [AssetMovementLeg(
                direction: .outflow,
                amount: "2 SOL",
                asset: "SOL",
                counterparty: nil
            )]),
            resolvedMints: [:]
        )
        let decoded = try InstructionDecoder().decode(
            instruction, accounts: ["vaultAddr"], specs: [program: [stakeSpec()]], crossCheck: context
        )
        #expect(decoded.kind == "Stake")
        #expect(decoded.crossCheck == .confirmed)
    }

    @Test func defaultedCrossCheckLeavesVerdictNil() throws {
        let instruction = SquadDecodedInstruction(
            program: program,
            kind: "raw",
            summary: "",
            rawDataHex: "0e0094357700000000"
        )
        let decoded = try InstructionDecoder().decode(instruction, accounts: [], specs: [program: [stakeSpec()]])
        #expect(decoded.crossCheck == nil)
    }
}
