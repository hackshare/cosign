import Foundation
import Testing
@testable import Indexer

struct AnchorIDLDocumentTests {
    private func decode(_ json: String) throws -> AnchorIDLDocument {
        try JSONDecoder().decode(AnchorIDLDocument.self, from: Data(json.utf8))
    }

    @Test func decodesNewFormatWithExplicitDiscriminator() throws {
        let json = """
        {
          "address": "whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc",
          "metadata": { "name": "whirlpool", "version": "0.3.0" },
          "instructions": [
            {
              "name": "swap",
              "discriminator": [248, 198, 158, 145, 225, 117, 135, 200],
              "accounts": [],
              "args": [
                { "name": "amount", "type": "u64" },
                { "name": "otherAmountThreshold", "type": "u64" }
              ]
            }
          ]
        }
        """
        let document = try decode(json)

        #expect(document.name == "whirlpool")
        #expect(document.instructions.count == 1)
        #expect(document.instructions[0].name == "swap")
        #expect(document.instructions[0].discriminator == [248, 198, 158, 145, 225, 117, 135, 200])
        #expect(document.instructions[0].arguments.map(\.name) == ["amount", "otherAmountThreshold"])
        #expect(document.instructions[0].arguments.allSatisfy { $0.type == .u64 })
    }

    @Test func computesLegacyDiscriminatorFromName() throws {
        let json = """
        {
          "version": "0.1.0",
          "name": "demo",
          "instructions": [
            { "name": "initialize", "accounts": [], "args": [] }
          ]
        }
        """
        let document = try decode(json)

        // sha256("global:initialize")[0..<8] is Anchor's well-known initialize sighash.
        #expect(document.instructions[0].discriminator == [175, 175, 109, 31, 13, 152, 155, 237])
    }

    @Test func snakeCasesCamelInstructionNamesForSighash() {
        #expect(AnchorIDLDocument.snakeCased("openPosition") == "open_position")
        #expect(AnchorIDLDocument.snakeCased("initialize") == "initialize")
        #expect(AnchorIDLDocument.snakeCased("swap") == "swap")
    }

    @Test func mapsPrimitiveAndCompositeTypes() throws {
        let json = """
        {
          "name": "demo",
          "instructions": [
            {
              "name": "act",
              "args": [
                { "name": "a", "type": "u64" },
                { "name": "b", "type": "publicKey" },
                { "name": "c", "type": { "vec": "u8" } },
                { "name": "d", "type": { "defined": "Config" } }
              ]
            }
          ]
        }
        """
        let types = try decode(json).instructions[0].arguments.map(\.type)
        #expect(types == [.u64, .pubkey, .other, .other])
    }
}
