import Foundation
import Testing
@testable import Indexer

struct AssetMovementTests {
    private func effect(
        kind: String = "transfer",
        asset: String? = nil,
        amount: String? = nil,
        source: String? = nil,
        destination: String? = nil
    ) -> RelayInspectionEffect {
        RelayInspectionEffect(
            kind: kind, summary: "", program: nil,
            asset: asset, amount: amount, source: source, destination: destination
        )
    }

    private let vault = "VAULT"

    @Test func outflowFromOwnAccountGoesToDestination() {
        let movement = AssetMovement.build(from: [
            effect(asset: "SOL", amount: "250", source: vault, destination: "Pool")
        ], ownAccounts: [vault])
        #expect(movement.legs.count == 1)
        #expect(movement.legs[0].direction == .outflow)
        #expect(movement.legs[0].counterparty == "Pool")
        #expect(movement.legs[0].amount == "250")
        #expect(movement.legs[0].asset == "SOL")
    }

    @Test func inflowToOwnAccountComesFromSource() {
        let movement = AssetMovement.build(from: [
            effect(asset: "USDC", amount: "18000", source: "Jupiter", destination: vault)
        ], ownAccounts: [vault])
        #expect(movement.legs.count == 1)
        #expect(movement.legs[0].direction == .inflow)
        #expect(movement.legs[0].counterparty == "Jupiter")
    }

    @Test func swapProducesOneOutflowAndOneInflow() {
        let movement = AssetMovement.build(from: [
            effect(asset: "SOL", amount: "250", source: vault, destination: "Pool"),
            effect(asset: "USDC", amount: "18000", source: "Pool", destination: vault)
        ], ownAccounts: [vault])
        #expect(movement.legs.count == 2)
        #expect(movement.legs[0].direction == .outflow)
        #expect(movement.legs[1].direction == .inflow)
    }

    @Test func effectTouchingNoOwnAccountIsSkipped() {
        let movement = AssetMovement.build(from: [
            effect(asset: "USDC", amount: "1", source: "X", destination: "Y")
        ], ownAccounts: [vault])
        #expect(movement.isEmpty)
    }

    @Test func burnFromOwnAccountHasNoCounterparty() {
        let movement = AssetMovement.build(from: [
            effect(kind: "burn", asset: "JTO", amount: "5", source: vault, destination: nil)
        ], ownAccounts: [vault])
        #expect(movement.legs.count == 1)
        #expect(movement.legs[0].direction == .outflow)
        #expect(movement.legs[0].counterparty == nil)
    }

    @Test func mintToOwnAccountHasNoCounterparty() {
        let movement = AssetMovement.build(from: [
            effect(kind: "mint", asset: "JTO", amount: "5", source: nil, destination: vault)
        ], ownAccounts: [vault])
        #expect(movement.legs.count == 1)
        #expect(movement.legs[0].direction == .inflow)
        #expect(movement.legs[0].counterparty == nil)
    }

    @Test func sourceOwnTakesPrecedenceWhenBothOwn() {
        let movement = AssetMovement.build(from: [
            effect(asset: "SOL", amount: "1", source: vault, destination: vault)
        ], ownAccounts: [vault])
        #expect(movement.legs.count == 1)
        #expect(movement.legs[0].direction == .outflow)
    }

    @Test func effectMissingAmountOrAssetIsSkipped() {
        let movement = AssetMovement.build(from: [
            effect(asset: nil, amount: "100", source: vault, destination: "B"),
            effect(asset: "USDC", amount: nil, source: vault, destination: "B")
        ], ownAccounts: [vault])
        #expect(movement.isEmpty)
    }

    @Test func emptyEffectsProduceEmptyMovement() {
        let movement = AssetMovement.build(from: [], ownAccounts: [vault])
        #expect(movement.isEmpty)
        #expect(movement.primaryLeg == nil)
    }

    @Test func primaryLegIsFirstLeg() {
        let movement = AssetMovement.build(from: [
            effect(asset: "SOL", amount: "1", source: vault, destination: "B")
        ], ownAccounts: [vault])
        #expect(movement.primaryLeg == movement.legs.first)
    }
}
