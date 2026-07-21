import Foundation
import Testing
@testable import Indexer

struct DecodeSpecTests {
    private func decode(_ json: String) throws -> DecodeSpec {
        try JSONDecoder().decode(DecodeSpec.self, from: Data(json.utf8))
    }

    @Test func decodesBindIdlWithStringTemplate() throws {
        let json = """
        {
          "program": "KLend2g3cP87fffoy8q1mQqGKjrxjC8boSyAYavgmjD",
          "discriminator": [1,2,3,4,5,6,7,8],
          "mode": "bind-idl",
          "bindsIdlHash": "abc123",
          "action": "Deposit",
          "accounts": { "userSourceTokenAccount": 4, "vault": 1 },
          "template": "Deposit {liquidityAmount:token(userSourceTokenAccount)} into Kamino",
          "effects": [
            { "direction": "out", "asset": "token(userSourceTokenAccount)", "amount": "arg(liquidityAmount)" }
          ]
        }
        """
        let spec = try decode(json)
        #expect(spec.mode == .bindIdl)
        #expect(spec.discriminator == [1, 2, 3, 4, 5, 6, 7, 8])
        #expect(spec.bindsIdlHash == "abc123")
        #expect(spec.accounts["userSourceTokenAccount"] == 4)
        #expect(spec.template.count == 1)
        #expect(spec.template[0].when.isEmpty)
        #expect(spec.template[0].text.contains("into Kamino"))
        #expect(spec.effects[0].direction == .out)
        #expect(spec.effects[0].when.isEmpty)
        #expect(spec.layout == nil)
    }

    @Test func decodesConditionalTemplateVariants() throws {
        let json = """
        {
          "program": "whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc",
          "discriminator": [248,198,158,145,225,117,135,200],
          "mode": "bind-idl",
          "action": "Swap",
          "accounts": { "userAccountA": 3, "userAccountB": 5 },
          "template": [
            { "when": ["arg(aToB)"],  "text": "Swap A for B" },
            { "when": ["!arg(aToB)"], "text": "Swap B for A" }
          ],
          "effects": [
            { "when": ["arg(aToB)"], "direction": "out", "asset": "token(userAccountA)", "amount": "arg(amount)" },
            { "when": ["!arg(aToB)"], "direction": "in", "asset": "token(userAccountA)", "amountAtLeast": "arg(otherAmountThreshold)" }
          ]
        }
        """
        let spec = try decode(json)
        #expect(spec.template.count == 2)
        #expect(spec.template[0].when == ["arg(aToB)"])
        #expect(spec.template[1].when == ["!arg(aToB)"])
        #expect(spec.effects[1].direction == .in)
        #expect(spec.effects[1].amountAtLeast == "arg(otherAmountThreshold)")
    }

    @Test func decodesStandaloneWithLayout() throws {
        let json = """
        {
          "program": "SPoo1Ku8WFXoNDMHPsrGSTSG1Y47rzgn41SLUNakuHy",
          "discriminator": [14],
          "mode": "standalone",
          "layout": [ { "name": "lamports", "type": "u64" } ],
          "action": "Stake",
          "accounts": { "vault": 0 },
          "template": "Stake {lamports:sol}",
          "effects": [ { "direction": "out", "asset": "SOL", "amount": "arg(lamports)" } ]
        }
        """
        let spec = try decode(json)
        #expect(spec.mode == .standalone)
        #expect(spec.discriminator == [14])
        #expect(spec.layout?.count == 1)
        #expect(spec.layout?[0].name == "lamports")
        #expect(spec.layout?[0].type == .u64)
    }

    @Test func decodesBundle() throws {
        let json = """
        { "schema": 1, "keyId": "cosign-registry-2026", "specs": [] }
        """
        let bundle = try JSONDecoder().decode(DecodeRegistryBundle.self, from: Data(json.utf8))
        #expect(bundle.schema == 1)
        #expect(bundle.keyId == "cosign-registry-2026")
        #expect(bundle.specs.isEmpty)
    }
}
