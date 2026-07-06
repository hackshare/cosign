import Foundation

/// A single directional leg of an asset movement, derived from one decoded
/// effect classified against the squad's own accounts. An effect whose source is
/// an own account is an outflow whose counterparty is the destination ("to"); an
/// effect whose destination is an own account is an inflow whose counterparty is
/// the source ("from").
public struct AssetMovementLeg: Equatable, Sendable {
    public enum Direction: Equatable, Sendable {
        case outflow
        case inflow
    }

    public let direction: Direction
    public let amount: String
    public let asset: String
    /// The other party: the destination for an outflow, the source for an inflow.
    public let counterparty: String?

    public init(direction: Direction, amount: String, asset: String, counterparty: String?) {
        self.direction = direction
        self.amount = amount
        self.asset = asset
        self.counterparty = counterparty
    }
}

/// The movement a transaction makes, built purely from decoded effects so it is
/// identical for a predicted (simulated) proposal and an executed (traced) one.
/// Direction is relative to the squad: an effect leaving an own account is an
/// outflow, one arriving at an own account is an inflow.
public struct AssetMovement: Equatable, Sendable {
    public let legs: [AssetMovementLeg]

    public init(legs: [AssetMovementLeg]) {
        self.legs = legs
    }

    public var isEmpty: Bool {
        legs.isEmpty
    }

    public var primaryLeg: AssetMovementLeg? {
        legs.first
    }

    public static func build(
        from effects: [RelayInspectionEffect],
        ownAccounts: Set<String>
    ) -> AssetMovement {
        var legs = [AssetMovementLeg]()
        for effect in effects {
            guard let amount = effect.amount, let asset = effect.asset else {
                continue
            }
            if let source = effect.source, ownAccounts.contains(source) {
                legs.append(AssetMovementLeg(
                    direction: .outflow, amount: amount, asset: asset, counterparty: effect.destination
                ))
            } else if let destination = effect.destination, ownAccounts.contains(destination) {
                legs.append(AssetMovementLeg(
                    direction: .inflow, amount: amount, asset: asset, counterparty: effect.source
                ))
            }
        }
        return AssetMovement(legs: legs)
    }
}
