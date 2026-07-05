import Core
import CosignCore
import Foundation
import Indexer
import SwiftUI

extension CreateSquadView {
    @MainActor
    func refreshBalance() async {
        if demoMode?.disablesNetworkWrites == true {
            balanceLamports = 2_000_000_000
            return
        }
        balanceLamports = try? await squadsService.solBalance(of: memberAddress)
    }

    @MainActor
    func addMember() {
        let candidate = newMember.trimmingCharacters(in: .whitespacesAndNewlines)
        guard CosignCore.isValidSolanaPubkey(candidate) else {
            memberError = CosignCopy.CreateSquad.invalidAddress
            return
        }
        guard candidate != memberAddress, !extraMembers.contains(candidate) else {
            memberError = CosignCopy.CreateSquad.duplicateAddress
            return
        }
        extraMembers.append(candidate)
        newMember = ""
        memberError = nil
    }

    @MainActor
    func removeMember(_ address: String) {
        extraMembers.removeAll { $0 == address }
        if threshold > memberCount { threshold = memberCount }
    }

    @MainActor
    func requestAirdrop() async {
        isAirdropping = true
        airdropFailed = false
        defer { isAirdropping = false }
        do {
            _ = try await squadsService.requestAirdrop(
                address: memberAddress,
                airdropRPCURL: indexerEnvironment.airdropRPCURL.absoluteString
            )
            try? await Task.sleep(for: .seconds(2))
            await refreshBalance()
        } catch {
            airdropFailed = true
        }
    }

    @MainActor
    func loadCost() async {
        if demoMode?.disablesNetworkWrites == true {
            cost = CreateMultisigCost(networkFee: 10000, rent: 1_900_000, creationFee: 0, total: 1_910_000)
            return
        }
        cost = try? await squadsService.estimateSquadCost(
            memberAddresses: extraMembers,
            threshold: UInt16(threshold),
            creatorPubkey: memberAddress
        )
    }

    @MainActor
    func create() async {
        if demoMode?.disablesNetworkWrites == true {
            createError = CosignCopy.CreateSquad.demoDisabled
            return
        }
        guard let registered = registeredSigners.first(where: { CosignCore.base58($0.pubkey) == memberAddress }),
              let actionSigner = makeProposalActionSigner(from: registered)
        else {
            createError = CosignCopy.CreateSquad.noActiveSigner
            return
        }
        isCreating = true
        createError = nil
        defer { isCreating = false }
        do {
            result = try await withResolvedProposalSigner(
                actionSigner,
                deviceStatus: { _ in },
                operation: { signer in
                    try await squadsService.createSquad(
                        memberAddresses: extraMembers,
                        threshold: UInt16(threshold),
                        signer: signer
                    )
                }
            )
        } catch {
            createError = CosignCopy.CreateSquad.createFailed(error.localizedDescription)
        }
    }

    func explorerURL(for address: String) -> URL? {
        SolanaExplorer.addressURL(address: address, rpcURL: indexerEnvironment.effectiveExplorerRPCURL)
    }
}
