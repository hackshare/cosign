import Foundation
import Indexer
import Testing
@testable import Squads

struct InstructionDecoderSpecTests {
    private let program = "SPoo1Ku8WFXoNDMHPsrGSTSG1Y47rzgn41SLUNakuHy"

    private func stakeSpec() throws -> DecodeSpec {
        let json = """
        { "program": "\(program)", "discriminator": [14], "mode": "standalone",
          "layout": [ { "name": "lamports", "type": "u64" } ], "action": "Stake", "accounts": {},
          "template": "Stake {lamports:sol}", "effects": [] }
        """
        return try JSONDecoder().decode(DecodeSpec.self, from: Data(json.utf8))
    }

    @Test func tier3SpecWinsOverFallback() throws {
        let instruction = SquadDecodedInstruction(
            program: program, kind: "raw", summary: "", rawDataHex: "0e" + "0094357700000000"
        )
        let decoded = try InstructionDecoder().decode(instruction, accounts: [], specs: [program: [stakeSpec()]])
        #expect(decoded.kind == "Stake")
        #expect(decoded.summary == "Stake 2 SOL")
    }

    @Test func fallsBackWhenNoSpecProvided() {
        let instruction = SquadDecodedInstruction(
            program: program,
            kind: "raw",
            summary: "",
            rawDataHex: "0e0094357700000000"
        )
        let decoded = InstructionDecoder().decode(instruction, accounts: [])
        #expect(decoded.kind == "raw")
        #expect(decoded.provenance == nil)
    }
}
