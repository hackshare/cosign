import Testing
@testable import Core

struct NetworkTests {
    @Test func rawValuesAreStable() {
        #expect(Network.mainnet.rawValue == "mainnet")
        #expect(Network.devnet.rawValue == "devnet")
    }

    @Test func displayNamesAndFlag() {
        #expect(Network.mainnet.displayName == "Mainnet")
        #expect(Network.devnet.displayName == "Devnet")
        #expect(Network.mainnet.isMainnet == true)
        #expect(Network.devnet.isMainnet == false)
    }
}
