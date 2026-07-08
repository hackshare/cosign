import Core
import CosignCore
import Foundation
import Indexer
import Squads
import SwiftUI

extension ManageSquadConfigView {
    // MARK: - Load

    @MainActor
    func load() async {
        loadError = false
        do {
            let loaded = try await squadsService.refreshDetail(of: squadAddress)
            detail = loaded
            desiredMembers = loaded.members
            removedKeys = []
            rentCollector = loaded.rentCollector
            threshold = Int(loaded.threshold)
            timeLockSeconds = loaded.timeLockSeconds
        } catch {
            loadError = true
        }
    }

    // MARK: - Member editing

    @MainActor
    func addMember() {
        let candidate = newMember.trimmingCharacters(in: .whitespacesAndNewlines)
        guard CosignCore.isValidSolanaPubkey(candidate) else {
            memberError = CosignCopy.ManageSquad.invalidAddress
            return
        }
        let alreadyPresent = desiredMembers.contains(where: { $0.pubkey == candidate })
        let alreadyRemoved = removedKeys.contains(candidate)
        guard !alreadyPresent, !alreadyRemoved else {
            memberError = CosignCopy.ManageSquad.duplicateAddress
            return
        }
        desiredMembers.append(SquadMember(pubkey: candidate, canInitiate: true, canVote: true, canExecute: true))
        newMember = ""
        memberError = nil
    }

    @MainActor
    func removeAddedMember(_ pubkey: String) {
        desiredMembers.removeAll { $0.pubkey == pubkey }
    }

    @MainActor
    func toggleMemberRemoval(_ pubkey: String, original: SquadMember) {
        if removedKeys.contains(pubkey) {
            removedKeys.remove(pubkey)
            // Restore in original sorted position relative to remaining desired members.
            if let detail, let idx = detail.members.firstIndex(where: { $0.pubkey == pubkey }) {
                let insertAt = desiredMembers.count(where: { mem in
                    guard let pos = detail.members.firstIndex(where: { $0.pubkey == mem.pubkey }) else { return false }
                    return pos < idx
                })
                desiredMembers.insert(original, at: min(insertAt, desiredMembers.count))
            } else {
                desiredMembers.append(original)
            }
        } else {
            removedKeys.insert(pubkey)
            desiredMembers.removeAll { $0.pubkey == pubkey }
        }
    }

    @MainActor
    func flipPermission(at index: Int, propose: Bool = false, vote: Bool = false, execute: Bool = false) {
        guard index < desiredMembers.count else { return }
        let current = desiredMembers[index]
        desiredMembers[index] = SquadMember(
            pubkey: current.pubkey,
            canInitiate: propose ? !current.canInitiate : current.canInitiate,
            canVote: vote ? !current.canVote : current.canVote,
            canExecute: execute ? !current.canExecute : current.canExecute
        )
    }

    @MainActor
    func clampThreshold() {
        let max = max(1, projectedVoterCount)
        if threshold > max { threshold = max }
    }

    // MARK: - Rent collector

    @MainActor
    func setRentCollector() {
        let candidate = rentCollectorInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else {
            rentCollectorError = nil
            return
        }
        guard CosignCore.isValidSolanaPubkey(candidate) else {
            rentCollectorError = CosignCopy.ManageSquad.invalidAddress
            return
        }
        rentCollector = candidate
        rentCollectorInput = ""
        rentCollectorError = nil
    }

    @MainActor
    func clearRentCollector() {
        rentCollector = nil
    }

    // MARK: - Time lock

    @MainActor
    func applyCustomTimeLock() {
        // numberPad prevents typing "." but a paste can include non-digit characters
        // (e.g. "1.5" parses as 15). That is a minor inaccuracy rather than data loss;
        // the out-of-range validation banner catches any result over the 90-day limit.
        let digits = timeLockCustomValue.filter(\.isNumber)
        // Clamp to a UInt32-overflow-safe bound rather than the 90-day limit, so an
        // over-limit entry still reaches `timeLockSeconds` and surfaces the range
        // banner. A paste too large to parse falls back to that bound instead of
        // silently resetting to Off.
        let maxForUnit = UInt64(UInt32.max) / UInt64(timeLockCustomUnit.seconds)
        let value = min(UInt64(digits) ?? maxForUnit, maxForUnit)
        timeLockSeconds = UInt32(value * UInt64(timeLockCustomUnit.seconds))
    }

    // MARK: - Create proposal

    @MainActor
    func create() async {
        if demoMode?.disablesNetworkWrites == true {
            createError = CosignCopy.ManageSquad.demoDisabled
            return
        }
        guard let detail else { return }
        let memberInitiators = detail.members.filter(\.canInitiate).map(\.pubkey)
        guard
            let registered = registeredSigners
            .first(where: { memberInitiators.contains(CosignCore.base58($0.pubkey)) }),
            let actionSigner = makeProposalActionSigner(from: registered)
        else {
            createError = CosignCopy.ManageSquad.noEligibleSigner
            return
        }
        isCreating = true
        createError = nil
        defer { isCreating = false }
        do {
            let submittedMembers = desiredMembers
            let submittedThreshold = UInt16(threshold)
            let submittedTimeLock = timeLockSeconds
            let submittedRentCollector = rentCollector
            let submission = try await withResolvedProposalSigner(
                actionSigner,
                deviceStatus: { _ in },
                operation: { signer in
                    try await squadsService.submitConfigChangeProposal(
                        desiredMembers: submittedMembers,
                        newThreshold: submittedThreshold,
                        newTimeLockSeconds: submittedTimeLock,
                        newRentCollector: submittedRentCollector,
                        expectedMembers: detail.members,
                        expectedThreshold: detail.threshold,
                        expectedTimeLockSeconds: detail.timeLockSeconds,
                        expectedRentCollector: detail.rentCollector,
                        in: squadAddress,
                        signer: signer
                    )
                }
            )
            coordinator.replaceCurrent(
                with: .proposalDetail(squad: squadAddress, txIndex: submission.transactionIndex)
            )
        } catch let error as ConfigChangeError {
            createError = configChangeErrorMessage(error)
        } catch {
            createError = CosignCopy.ManageSquad.createFailed(error.localizedDescription)
        }
    }

    private func configChangeErrorMessage(_ error: ConfigChangeError) -> String {
        switch error {
        case .notAutonomous:
            CosignCopy.ManageSquad.controlledNote
        case .invalidMemberAddress:
            CosignCopy.ManageSquad.invalidAddress
        case .contradictoryEdit:
            CosignCopy.ManageSquad.contradictoryEditError
        case .memberMissingPermission:
            CosignCopy.ManageSquad.memberMissingPermission
        case .noChanges:
            CosignCopy.ManageSquad.noChangesError
        case .thresholdOutOfRange:
            CosignCopy.ManageSquad.thresholdTooHigh
        case .timeLockOutOfRange:
            CosignCopy.ManageSquad.timeLockOutOfRange
        }
    }

    // MARK: - Computed

    var projectedVoterCount: Int {
        desiredMembers.count(where: \.canVote)
    }

    var hasChanges: Bool {
        guard let detail else { return false }
        let memberKey = { (member: SquadMember) -> String in
            "\(member.pubkey):\(member.canInitiate ? 1 : 0)\(member.canVote ? 1 : 0)\(member.canExecute ? 1 : 0)"
        }
        let desiredSet = Set(desiredMembers.map(memberKey))
        let currentSet = Set(detail.members.map(memberKey))
        return desiredSet != currentSet
            || threshold != Int(detail.threshold)
            || timeLockSeconds != detail.timeLockSeconds
            || rentCollector != detail.rentCollector
    }

    var validationError: String? {
        if desiredMembers.contains(where: { !$0.canInitiate && !$0.canVote && !$0.canExecute }) {
            return CosignCopy.ManageSquad.memberMissingPermission
        }
        let voters = desiredMembers.count(where: \.canVote)
        guard voters >= 1 else {
            return CosignCopy.ManageSquad.noVotersRemain
        }
        guard threshold >= 1 else {
            return CosignCopy.ManageSquad.thresholdTooLow
        }
        guard threshold <= voters else {
            return CosignCopy.ManageSquad.thresholdTooHigh
        }
        let proposers = desiredMembers.count(where: \.canInitiate)
        guard proposers >= 1 else {
            return CosignCopy.ManageSquad.noProposersRemain
        }
        let executors = desiredMembers.count(where: \.canExecute)
        guard executors >= 1 else {
            return CosignCopy.ManageSquad.noExecutorsRemain
        }
        guard timeLockSeconds <= SquadsService.maxTimeLockSeconds else {
            return CosignCopy.ManageSquad.timeLockOutOfRange
        }
        return nil
    }

    var canCreate: Bool {
        hasChanges && validationError == nil
    }

    var currentSignerAddresses: Set<String> {
        Set(registeredSigners.map { CosignCore.base58($0.pubkey) })
    }

    var hasSelfRemoval: Bool {
        !removedKeys.isDisjoint(with: currentSignerAddresses)
    }

    var memberDiffTitle: String {
        guard let detail else { return "" }
        let originalKeys = Set(detail.members.map(\.pubkey))
        let addedCount = desiredMembers.count(where: { !originalKeys.contains($0.pubkey) })
        let changedCount = desiredMembers.count(where: { member in
            guard let original = detail.members.first(where: { $0.pubkey == member.pubkey }) else { return false }
            return original.canInitiate != member.canInitiate
                || original.canVote != member.canVote
                || original.canExecute != member.canExecute
        })
        let removedCount = removedKeys.count
        return CosignCopy.ManageSquad.memberChangeDiff(added: addedCount, changed: changedCount, removed: removedCount)
    }
}
