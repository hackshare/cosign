import Foundation
import Indexer
import Testing
@testable import Squads

struct InstructionDecoderIDLTests {
    private let program = "whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc"

    private func resolvedSwap() throws -> ResolvedProgramIDL {
        let json = """
        {
          "metadata": { "name": "whirlpool" },
          "instructions": [
            { "name": "swap", "discriminator": [1, 2, 3, 4, 5, 6, 7, 8],
              "args": [ { "name": "amount", "type": "u64" } ] }
          ]
        }
        """
        let document = try JSONDecoder().decode(AnchorIDLDocument.self, from: Data(json.utf8))
        return ResolvedProgramIDL(
            document: document,
            provenance: .onChainIDL(idlName: "whirlpool", hash: "abc123", slot: 7)
        )
    }

    @Test func usesIDLTierForUnknownProgramWhenProvided() throws {
        let instruction = SquadDecodedInstruction(
            program: program, kind: "raw", summary: "",
            rawDataHex: "0102030405060708" + "40420f0000000000"
        )
        let decoded = try InstructionDecoder().decode(
            instruction,
            accounts: [],
            idls: [program: resolvedSwap()]
        )
        #expect(decoded.kind == "swap")
        #expect(decoded.summary == "swap(amount: 1000000)")
        #expect(decoded.provenance == .onChainIDL(idlName: "whirlpool", hash: "abc123", slot: 7))
    }

    @Test func fallsBackWhenNoIDLProvided() {
        let instruction = SquadDecodedInstruction(
            program: program, kind: "raw", summary: "",
            rawDataHex: "0102030405060708" + "40420f0000000000"
        )
        let decoded = InstructionDecoder().decode(instruction, accounts: [])
        #expect(decoded.kind == "raw")
        #expect(decoded.provenance == nil)
    }

    @Test func programsNeedingIDLListsOnlyUnrecognizedPrograms() {
        // The System transfer decodes to a primitive (kind "transfer"); the whirlpool
        // instruction hits the fallback (kind "raw"), so only its program is listed.
        let proposal = SquadProposalDetail(
            transactionIndex: 1,
            status: "Active",
            votesYes: 0,
            votesNo: 0,
            votesCancelled: 0,
            threshold: 1,
            kind: "vault",
            votersYes: [],
            votersNo: [],
            votersCancelled: [],
            instructions: [
                SquadDecodedInstruction(
                    program: "11111111111111111111111111111111", kind: "raw", summary: "",
                    rawDataHex: "020000008813000000000000"
                ),
                SquadDecodedInstruction(
                    program: program, kind: "raw", summary: "", rawDataHex: "0102030405060708"
                )
            ],
            accountsReferenced: [],
            transactionAddress: nil
        )
        #expect(InstructionDecoder().programsNeedingIDL(in: proposal) == [program])
    }
}
