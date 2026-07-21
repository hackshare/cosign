import Foundation
import Indexer
import Testing
@testable import Squads

struct AnchorIDLInterpreterTests {
    private func resolved(_ json: String, slot: UInt64 = 100) throws -> ResolvedProgramIDL {
        let document = try JSONDecoder().decode(AnchorIDLDocument.self, from: Data(json.utf8))
        return ResolvedProgramIDL(
            document: document,
            provenance: .onChainIDL(idlName: document.name, hash: "deadbeefcafe", slot: slot)
        )
    }

    private let swapIDL = """
    {
      "metadata": { "name": "whirlpool" },
      "instructions": [
        {
          "name": "swap",
          "discriminator": [1, 2, 3, 4, 5, 6, 7, 8],
          "args": [
            { "name": "amount", "type": "u64" },
            { "name": "otherAmountThreshold", "type": "u64" }
          ]
        }
      ]
    }
    """

    @Test func decodesMatchingInstructionWithArgs() throws {
        // discriminator 01..08, then amount=1000000 (u64 LE), threshold=950000 (u64 LE).
        let data = "0102030405060708" + "40420f0000000000" + "f07e0e0000000000"
        let instruction = SquadDecodedInstruction(
            program: "whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc",
            kind: "raw",
            summary: "",
            rawDataHex: data
        )

        let display = try AnchorIDLInterpreter().interpret(
            instruction,
            resolved: resolved(swapIDL),
            accounts: ["a", "b"]
        )

        #expect(display?.programLabel == "whirlpool")
        #expect(display?.kind == "swap")
        #expect(display?.summary == "swap(amount: 1000000, otherAmountThreshold: 950000)")
        #expect(display?.accounts == ["a", "b"])
        #expect(display?.provenance == .onChainIDL(idlName: "whirlpool", hash: "deadbeefcafe", slot: 100))
    }

    @Test func returnsNilWhenNoDiscriminatorMatches() throws {
        let instruction = SquadDecodedInstruction(
            program: "whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc",
            kind: "raw",
            summary: "",
            rawDataHex: "aaaaaaaaaaaaaaaa" + "40420f0000000000"
        )
        #expect(try AnchorIDLInterpreter().interpret(instruction, resolved: resolved(swapIDL), accounts: []) == nil)
    }

    @Test func returnsNilWhenDataTooShort() throws {
        let instruction = SquadDecodedInstruction(
            program: "x",
            kind: "raw",
            summary: "",
            rawDataHex: "0102"
        )
        #expect(try AnchorIDLInterpreter().interpret(instruction, resolved: resolved(swapIDL), accounts: []) == nil)
    }

    @Test func rendersNamesOnlyAfterAnUnknownArgType() throws {
        let idl = """
        {
          "name": "demo",
          "instructions": [
            {
              "name": "act",
              "discriminator": [9, 9, 9, 9, 9, 9, 9, 9],
              "args": [
                { "name": "flag", "type": "u8" },
                { "name": "config", "type": { "defined": "Config" } },
                { "name": "tail", "type": "u64" }
              ]
            }
          ]
        }
        """
        let instruction = SquadDecodedInstruction(
            program: "x", kind: "raw", summary: "", rawDataHex: "0909090909090909" + "01" + "ffff"
        )
        let display = try AnchorIDLInterpreter().interpret(instruction, resolved: resolved(idl), accounts: [])
        #expect(display?.summary == "act(flag: 1, config, tail)")
    }
}
