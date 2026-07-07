import XCTest
@testable import Squads

final class ConfigChangeValidationTests: XCTestCase {
    // Two well-known Solana program addresses — both pass isValidSolanaPubkey.
    let signerKey = "So11111111111111111111111111111111111111112"
    let otherKey = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"

    /// Two full-permission members, threshold 2, autonomous by default.
    func makeTwoOfTwo(autonomous: Bool = true) -> SquadDetail {
        SquadDetail(
            address: signerKey,
            threshold: 2,
            timeLockSeconds: 0,
            transactionIndex: 1,
            staleTransactionIndex: 0,
            isAutonomous: autonomous,
            members: [
                SquadMember(pubkey: signerKey, canInitiate: true, canVote: true, canExecute: true),
                SquadMember(pubkey: otherKey, canInitiate: true, canVote: true, canExecute: true)
            ],
            vaults: []
        )
    }

    func testNotAutonomousThrows() {
        XCTAssertThrowsError(try SquadsService.validateConfigChange(
            detail: makeTwoOfTwo(autonomous: false),
            memberPubkey: signerKey,
            addedMembers: [],
            removedMembers: [otherKey],
            newThreshold: 1,
            newTimeLockSeconds: 0
        )) { error in
            guard case ConfigChangeError.notAutonomous = error else {
                return XCTFail("expected notAutonomous, got \(error)")
            }
        }
    }

    func testSignerNotMemberThrows() {
        // Squad with only otherKey as a member; signerKey is not in it.
        let detail = SquadDetail(
            address: otherKey,
            threshold: 1,
            timeLockSeconds: 0,
            transactionIndex: 1,
            staleTransactionIndex: 0,
            isAutonomous: true,
            members: [
                SquadMember(pubkey: otherKey, canInitiate: true, canVote: true, canExecute: true)
            ],
            vaults: []
        )
        XCTAssertThrowsError(try SquadsService.validateConfigChange(
            detail: detail,
            memberPubkey: signerKey,
            addedMembers: [],
            removedMembers: [],
            newThreshold: 1,
            newTimeLockSeconds: 0
        )) { error in
            guard case ConfigChangeError.signerNotMember = error else {
                return XCTFail("expected signerNotMember, got \(error)")
            }
        }
    }

    func testMissingInitiatePermissionThrows() {
        let detail = SquadDetail(
            address: signerKey,
            threshold: 2,
            timeLockSeconds: 0,
            transactionIndex: 1,
            staleTransactionIndex: 0,
            isAutonomous: true,
            members: [
                SquadMember(pubkey: signerKey, canInitiate: false, canVote: true, canExecute: true),
                SquadMember(pubkey: otherKey, canInitiate: true, canVote: true, canExecute: true)
            ],
            vaults: []
        )
        XCTAssertThrowsError(try SquadsService.validateConfigChange(
            detail: detail,
            memberPubkey: signerKey,
            addedMembers: [],
            removedMembers: [otherKey],
            newThreshold: 1,
            newTimeLockSeconds: 0
        )) { error in
            guard case ConfigChangeError.missingInitiatePermission = error else {
                return XCTFail("expected missingInitiatePermission, got \(error)")
            }
        }
    }

    func testThresholdTooHighAfterRemovalThrows() {
        // 2-of-2 squad; remove otherKey but keep threshold at 2.
        // Projected voters = 1 (signerKey), threshold 2 > 1 → thresholdOutOfRange.
        XCTAssertThrowsError(try SquadsService.validateConfigChange(
            detail: makeTwoOfTwo(),
            memberPubkey: signerKey,
            addedMembers: [],
            removedMembers: [otherKey],
            newThreshold: 2,
            newTimeLockSeconds: 0
        )) { error in
            guard case ConfigChangeError.thresholdOutOfRange = error else {
                return XCTFail("expected thresholdOutOfRange, got \(error)")
            }
        }
    }

    func testRemoveOneAndLowerThresholdSucceeds() throws {
        // 2-of-2 squad; remove otherKey and lower threshold to 1.
        try SquadsService.validateConfigChange(
            detail: makeTwoOfTwo(),
            memberPubkey: signerKey,
            addedMembers: [],
            removedMembers: [otherKey],
            newThreshold: 1,
            newTimeLockSeconds: 0
        )
    }

    func testContradictoryEditAddExistingMemberThrows() {
        // otherKey is already a member — cannot add them again.
        XCTAssertThrowsError(try SquadsService.validateConfigChange(
            detail: makeTwoOfTwo(),
            memberPubkey: signerKey,
            addedMembers: [otherKey],
            removedMembers: [],
            newThreshold: 2,
            newTimeLockSeconds: 0
        )) { error in
            guard case ConfigChangeError.contradictoryEdit = error else {
                return XCTFail("expected contradictoryEdit, got \(error)")
            }
        }
    }

    func testContradictoryEditRemoveNonMemberThrows() {
        // Squad with only signerKey; otherKey is not a member.
        let detail = SquadDetail(
            address: signerKey,
            threshold: 1,
            timeLockSeconds: 0,
            transactionIndex: 1,
            staleTransactionIndex: 0,
            isAutonomous: true,
            members: [
                SquadMember(pubkey: signerKey, canInitiate: true, canVote: true, canExecute: true)
            ],
            vaults: []
        )
        XCTAssertThrowsError(try SquadsService.validateConfigChange(
            detail: detail,
            memberPubkey: signerKey,
            addedMembers: [],
            removedMembers: [otherKey],
            newThreshold: 1,
            newTimeLockSeconds: 0
        )) { error in
            guard case ConfigChangeError.contradictoryEdit = error else {
                return XCTFail("expected contradictoryEdit, got \(error)")
            }
        }
    }

    func testContradictoryEditAddAndRemoveSameKeyThrows() {
        // Squad with only signerKey; try to simultaneously add and remove otherKey.
        // The intersection check fires before the remove-non-member check.
        let detail = SquadDetail(
            address: signerKey,
            threshold: 1,
            timeLockSeconds: 0,
            transactionIndex: 1,
            staleTransactionIndex: 0,
            isAutonomous: true,
            members: [
                SquadMember(pubkey: signerKey, canInitiate: true, canVote: true, canExecute: true)
            ],
            vaults: []
        )
        XCTAssertThrowsError(try SquadsService.validateConfigChange(
            detail: detail,
            memberPubkey: signerKey,
            addedMembers: [otherKey],
            removedMembers: [otherKey],
            newThreshold: 1,
            newTimeLockSeconds: 0
        )) { error in
            guard case ConfigChangeError.contradictoryEdit = error else {
                return XCTFail("expected contradictoryEdit, got \(error)")
            }
        }
    }

    func testNoChangesThrows() {
        // No adds, no removes, threshold unchanged (2) → noChanges.
        XCTAssertThrowsError(try SquadsService.validateConfigChange(
            detail: makeTwoOfTwo(),
            memberPubkey: signerKey,
            addedMembers: [],
            removedMembers: [],
            newThreshold: 2,
            newTimeLockSeconds: 0
        )) { error in
            guard case ConfigChangeError.noChanges = error else {
                return XCTFail("expected noChanges, got \(error)")
            }
        }
    }

    func testTimeLockOverMaxThrows() {
        XCTAssertThrowsError(try SquadsService.validateConfigChange(
            detail: makeTwoOfTwo(),
            memberPubkey: signerKey,
            addedMembers: [],
            removedMembers: [],
            newThreshold: 2,
            newTimeLockSeconds: 7_776_001
        )) { error in
            guard case ConfigChangeError.timeLockOutOfRange = error else {
                return XCTFail("expected timeLockOutOfRange, got \(error)")
            }
        }
    }

    func testTimeLockChangeAloneIsValid() {
        XCTAssertNoThrow(try SquadsService.validateConfigChange(
            detail: makeTwoOfTwo(),
            memberPubkey: signerKey,
            addedMembers: [],
            removedMembers: [],
            newThreshold: 2,
            newTimeLockSeconds: 86400
        ))
    }
}
