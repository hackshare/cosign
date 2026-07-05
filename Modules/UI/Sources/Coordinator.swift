import Foundation
import Observation
import SwiftUI

public enum Route: Hashable, Sendable {
    case settings
    case networkSettings
    case selfHostedRelay
    case buildVerification
    case aboutCosign
    case signers
    case signerHome(UUID)
    case signerDetail(UUID)
    case signerSquads(String)
    case squadDetail(String)
    case vaultDetail(squad: String, vaultIndex: UInt8)
    case vaultInspection(squad: String, vaultIndex: UInt8)
    case createTransferProposal(squad: String, vaultIndex: UInt8?)
    case proposals(squad: String, latestIndex: UInt64)
    case proposalDetail(squad: String, txIndex: UInt64)
    case activity(squad: String)
    case transactionInspection(signature: String)
    case createSquad(memberAddress: String)
}

@MainActor
@Observable
public final class Coordinator {
    public var path = NavigationPath()

    public init() {}

    public func go(to route: Route) {
        path.append(route)
    }

    public func pop() {
        guard !path.isEmpty else {
            return
        }
        path.removeLast()
    }

    public func replaceCurrent(with route: Route) {
        if !path.isEmpty {
            path.removeLast()
        }
        path.append(route)
    }

    public func popToRoot() {
        path.removeLast(path.count)
    }
}
