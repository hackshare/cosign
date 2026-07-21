import Foundation
import Indexer
import Testing
@testable import Squads

struct DecodeSpecInterpreterTests {
    private func spec(_ json: String) throws -> DecodeSpec {
        try JSONDecoder().decode(DecodeSpec.self, from: Data(json.utf8))
    }

    @Test func interpretsStandaloneSpec() throws {
        let json = """
        {
          "program": "SPoo1Ku8WFXoNDMHPsrGSTSG1Y47rzgn41SLUNakuHy",
          "discriminator": [14],
          "mode": "standalone",
          "layout": [ { "name": "lamports", "type": "u64" } ],
          "action": "Stake",
          "accounts": { "vault": 0 },
          "template": "Stake {lamports:sol}",
          "effects": []
        }
        """
        // discriminator 0x0E, then lamports=2 SOL (2_000_000_000 u64 LE).
        let instruction = SquadDecodedInstruction(
            program: "SPoo1Ku8WFXoNDMHPsrGSTSG1Y47rzgn41SLUNakuHy",
            kind: "raw", summary: "", rawDataHex: "0e" + "00943577000000 00".replacingOccurrences(of: " ", with: "")
        )
        let display = try DecodeSpecInterpreter().interpret(
            instruction, spec: spec(json), resolvedIDL: nil, accounts: ["vaultAddr"], mints: [:]
        )
        #expect(display?.kind == "Stake")
        #expect(display?.summary == "Stake 2 SOL")
        if case let .registry(action, _, boundProgram)? = display?.provenance {
            #expect(action == "Stake")
            #expect(boundProgram == nil)
        } else {
            Issue.record("expected registry provenance")
        }
    }

    @Test func interpretsBindIdlSpecUsingIdlArgs() throws {
        let idlJSON = """
        { "metadata": { "name": "kamino" }, "instructions": [
          { "name": "deposit", "discriminator": [1,2,3,4,5,6,7,8],
            "args": [ { "name": "amount", "type": "u64" } ] } ] }
        """
        let document = try JSONDecoder().decode(AnchorIDLDocument.self, from: Data(idlJSON.utf8))
        let resolved = ResolvedProgramIDL(
            document: document,
            provenance: .onChainIDL(idlName: "kamino", hash: "h", slot: 1)
        )
        let specJSON = """
        { "program": "K", "discriminator": [1,2,3,4,5,6,7,8], "mode": "bind-idl", "bindsIdlHash": "h",
          "action": "Deposit", "accounts": {}, "template": "Deposit {amount}", "effects": [] }
        """
        let instruction = SquadDecodedInstruction(
            program: "K", kind: "raw", summary: "", rawDataHex: "0102030405060708" + "40420f0000000000"
        )
        let display = try DecodeSpecInterpreter().interpret(
            instruction, spec: spec(specJSON), resolvedIDL: resolved, accounts: [], mints: [:]
        )
        #expect(display?.summary == "Deposit 1000000")
        #expect(display?.kind == "Deposit")
    }

    @Test func bindIdlWithEmptyNameFallsBackToShortAddress() throws {
        let idlJSON = """
        { "instructions": [
          { "name": "deposit", "discriminator": [1,2,3,4,5,6,7,8],
            "args": [ { "name": "amount", "type": "u64" } ] } ] }
        """
        let document = try JSONDecoder().decode(AnchorIDLDocument.self, from: Data(idlJSON.utf8))
        #expect(document.name.isEmpty)
        let resolved = ResolvedProgramIDL(
            document: document,
            provenance: .onChainIDL(idlName: "", hash: "h", slot: 1)
        )
        let specJSON = """
        { "program": "K", "discriminator": [1,2,3,4,5,6,7,8], "mode": "bind-idl", "bindsIdlHash": "h",
          "action": "Deposit", "accounts": {}, "template": "Deposit {amount}", "effects": [] }
        """
        let instruction = SquadDecodedInstruction(
            program: "SoMeLongProgramAddress111111111111111111111",
            kind: "raw", summary: "", rawDataHex: "0102030405060708" + "40420f0000000000"
        )
        let display = try DecodeSpecInterpreter().interpret(
            instruction, spec: spec(specJSON), resolvedIDL: resolved, accounts: [], mints: [:]
        )
        let expectedLabel = InstructionDecoder.shortAddress("SoMeLongProgramAddress111111111111111111111")
        #expect(display?.programLabel == expectedLabel)
        #expect(display?.programLabel.isEmpty == false)
        if case let .registry(_, _, boundProgram)? = display?.provenance {
            #expect(boundProgram == nil)
        } else {
            Issue.record("expected registry provenance")
        }
        #expect(display?.provenance?.sourceDescription.contains("bound to") == false)
    }

    @Test func bindIdlDropsSpecWhenHashMismatch() throws {
        let idlJSON = """
        { "metadata": { "name": "kamino" }, "instructions": [
          { "name": "deposit", "discriminator": [1,2,3,4,5,6,7,8],
            "args": [ { "name": "amount", "type": "u64" } ] } ] }
        """
        let document = try JSONDecoder().decode(AnchorIDLDocument.self, from: Data(idlJSON.utf8))
        let resolved = ResolvedProgramIDL(
            document: document,
            provenance: .onChainIDL(idlName: "kamino", hash: "h", slot: 1)
        )
        let specJSON = """
        { "program": "K", "discriminator": [1,2,3,4,5,6,7,8], "mode": "bind-idl", "bindsIdlHash": "stale",
          "action": "Deposit", "accounts": {}, "template": "Deposit {amount}", "effects": [] }
        """
        let instruction = SquadDecodedInstruction(
            program: "K", kind: "raw", summary: "", rawDataHex: "0102030405060708" + "40420f0000000000"
        )
        let display = try DecodeSpecInterpreter().interpret(
            instruction, spec: spec(specJSON), resolvedIDL: resolved, accounts: [], mints: [:]
        )
        #expect(display == nil)
    }

    @Test func emptyDiscriminatorNeverMatches() throws {
        let json = """
        { "program": "P", "discriminator": [], "mode": "standalone", "layout": [],
          "action": "X", "accounts": {}, "template": "x", "effects": [] }
        """
        let instruction = SquadDecodedInstruction(program: "P", kind: "raw", summary: "", rawDataHex: "0e")
        #expect(try DecodeSpecInterpreter().interpret(
            instruction,
            spec: spec(json),
            resolvedIDL: nil,
            accounts: [],
            mints: [:]
        ) == nil)
    }

    @Test func returnsNilWhenDiscriminatorDoesNotMatch() throws {
        let json = """
        { "program": "P", "discriminator": [99], "mode": "standalone", "layout": [],
          "action": "X", "accounts": {}, "template": "x", "effects": [] }
        """
        let instruction = SquadDecodedInstruction(program: "P", kind: "raw", summary: "", rawDataHex: "0e")
        #expect(try DecodeSpecInterpreter().interpret(
            instruction,
            spec: spec(json),
            resolvedIDL: nil,
            accounts: [],
            mints: [:]
        ) == nil)
    }
}
