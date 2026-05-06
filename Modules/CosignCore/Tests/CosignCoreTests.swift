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
}
