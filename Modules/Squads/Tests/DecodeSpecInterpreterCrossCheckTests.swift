import Foundation
import Indexer
import Testing
@testable import Squads

struct DecodeSpecInterpreterCrossCheckTests {
    private func spec(_ json: String) throws -> DecodeSpec {
        try JSONDecoder().decode(DecodeSpec.self, from: Data(json.utf8))
    }

    private let program = "SPoo1Ku8WFXoNDMHPsrGSTSG1Y47rzgn41SLUNakuHy"

    private func stakeSpec() throws -> DecodeSpec {
        try spec(#"""
        { "program":"\#(program)","discriminator":[14],"mode":"standalone",
          "layout":[{"name":"lamports","type":"u64"}],"action":"Stake","accounts":{"vault":0,"poolMint":2},
          "template":"Stake {lamports:sol}",
          "effects":[
            {"direction":"out","asset":"SOL","amount":"arg(lamports)"},
            {"direction":"in","asset":"token(poolMint)","amountAtLeast":"0"}
          ] }
        """#)
    }

    private func instruction() -> SquadDecodedInstruction {
        SquadDecodedInstruction(program: program, kind: "raw", summary: "", rawDataHex: "0e" + "0094357700000000")
    }

    @Test func confirmedVerdictIsCarried() throws {
        let simulated = AssetMovement(legs: [
            AssetMovementLeg(direction: .outflow, amount: "2 SOL", asset: "SOL", counterparty: nil),
            AssetMovementLeg(direction: .inflow, amount: "1.9", asset: "POOLMINT", counterparty: nil)
        ])
        let context = CrossCheckContext(
            simulated: simulated, resolvedMints: ["POOLMINTACC": ResolvedMint(
                mint: "POOLMINT",
                decimals: 9,
                symbol: "JitoSOL"
            )]
        )
        let display = try DecodeSpecInterpreter().interpret(
            instruction(), spec: stakeSpec(), resolvedIDL: nil,
            accounts: ["vaultAddr", "x", "POOLMINTACC"], mints: [:], crossCheck: context
        )
        #expect(display?.summary == "Stake 2 SOL")
        #expect(display?.crossCheck == .confirmed)
    }

    @Test func contradictedVerdictIsCarried() throws {
        let simulated = AssetMovement(legs: [
            AssetMovementLeg(direction: .outflow, amount: "9 SOL", asset: "SOL", counterparty: nil)
        ])
        let context = CrossCheckContext(simulated: simulated, resolvedMints: [:])
        let display = try DecodeSpecInterpreter().interpret(
            instruction(), spec: stakeSpec(), resolvedIDL: nil,
            accounts: ["vaultAddr", "x", "POOLMINTACC"], mints: [:], crossCheck: context
        )
        #expect(display?.crossCheck == .contradicted)
    }

    @Test func noContextLeavesVerdictNil() throws {
        let display = try DecodeSpecInterpreter().interpret(
            instruction(), spec: stakeSpec(), resolvedIDL: nil,
            accounts: ["vaultAddr", "x", "POOLMINTACC"], mints: [:]
        )
        #expect(display?.crossCheck == nil)
    }

    @Test func m1PartialArgFallsThrough() throws {
        // Template references {amount} but the short buffer supplies no bytes past the tag.
        let sendSpec = try spec(#"""
        { "program":"\#(program)","discriminator":[14],"mode":"standalone",
          "layout":[{"name":"amount","type":"u64"}],"action":"X","accounts":{},
          "template":"Send {amount}","effects":[] }
        """#)
        let short = SquadDecodedInstruction(program: program, kind: "raw", summary: "", rawDataHex: "0e")
        #expect(
            DecodeSpecInterpreter().interpret(short, spec: sendSpec, resolvedIDL: nil, accounts: [], mints: [:]) == nil
        )
    }
}
