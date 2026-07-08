import XCTest
@testable import Squads

final class ConfigChangeValidationTests: XCTestCase {
    // Two well-known Solana program addresses -- both pass isValidSolanaPubkey.
    let signerKey = "So11111111111111111111111111111111111111112"
    let otherKey = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"

    /// Two full-permission members, threshold 2, autonomous by default.
    func makeTwoOfTwo(autonomous: Bool = true) -> SquadDetail {
        SquadDetail(
            address: signerKey,
            threshold: 2,
            timeLockSeconds: 0,
            rentCollector: nil,
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
        let detail = makeTwoOfTwo(autonomous: false)
        XCTAssertThrowsError(try SquadsService.validateConfigChange(
            detail: detail,
            desiredMembers: detail.members,
            newThreshold: 1,
            newTimeLockSeconds: 0,
            newRentCollector: nil
        )) { error in
            guard case ConfigChangeError.notAutonomous = error else {
                return XCTFail("expected notAutonomous, got \(error)")
            }
        }
    }

    func testDesiredNoOpThrows() {
        let detail = makeTwoOfTwo()
        XCTAssertThrowsError(try SquadsService.validateConfigChange(
            detail: detail,
            desiredMembers: detail.members,
            newThreshold: detail.threshold,
            newTimeLockSeconds: detail.timeLockSeconds,
            newRentCollector: detail.rentCollector
        )) { error in
            guard case ConfigChangeError.noChanges = error else {
                return XCTFail("expected noChanges, got \(error)")
            }
        }
    }

    func testPermissionEditIsValid() {
        let detail = makeTwoOfTwo()
        // Downgrade otherKey to vote-only; signerKey still provides propose and execute.
        let edited = detail.members.map { member -> SquadMember in
            member.pubkey == otherKey
                ? SquadMember(pubkey: otherKey, canInitiate: false, canVote: true, canExecute: false)
                : member
        }
        XCTAssertNoThrow(try SquadsService.validateConfigChange(
            detail: detail, desiredMembers: edited, newThreshold: 1,
            newTimeLockSeconds: detail.timeLockSeconds, newRentCollector: detail.rentCollector
        ))
    }

    func testZeroPermissionMemberThrows() {
        let detail = makeTwoOfTwo()
        let bad = detail.members.map { member -> SquadMember in
            member.pubkey == otherKey
                ? SquadMember(pubkey: otherKey, canInitiate: false, canVote: false, canExecute: false)
                : member
        }
        XCTAssertThrowsError(try SquadsService.validateConfigChange(
            detail: detail, desiredMembers: bad, newThreshold: 1,
            newTimeLockSeconds: detail.timeLockSeconds, newRentCollector: detail.rentCollector
        )) { error in
            guard case ConfigChangeError.memberMissingPermission = error else {
                return XCTFail("expected memberMissingPermission, got \(error)")
            }
        }
    }

    func testRentCollectorChangeAloneIsValid() {
        let detail = makeTwoOfTwo() // rentCollector nil
        XCTAssertNoThrow(try SquadsService.validateConfigChange(
            detail: detail, desiredMembers: detail.members, newThreshold: detail.threshold,
            newTimeLockSeconds: detail.timeLockSeconds, newRentCollector: signerKey
        ))
    }

    func testThresholdTooHighThrows() {
        // Remove otherKey from desired but keep threshold at 2: 1 voter, threshold 2 -> thresholdOutOfRange.
        let detail = makeTwoOfTwo()
        let desired = [SquadMember(pubkey: signerKey, canInitiate: true, canVote: true, canExecute: true)]
        XCTAssertThrowsError(try SquadsService.validateConfigChange(
            detail: detail,
            desiredMembers: desired,
            newThreshold: 2,
            newTimeLockSeconds: 0,
            newRentCollector: nil
        )) { error in
            guard case ConfigChangeError.thresholdOutOfRange = error else {
                return XCTFail("expected thresholdOutOfRange, got \(error)")
            }
        }
    }

    func testRemoveAndLowerThresholdSucceeds() throws {
        let detail = makeTwoOfTwo()
        let desired = [SquadMember(pubkey: signerKey, canInitiate: true, canVote: true, canExecute: true)]
        XCTAssertNoThrow(try SquadsService.validateConfigChange(
            detail: detail,
            desiredMembers: desired,
            newThreshold: 1,
            newTimeLockSeconds: 0,
            newRentCollector: nil
        ))
    }

    func testDuplicateMemberThrows() {
        let detail = makeTwoOfTwo()
        let desired = [
            SquadMember(pubkey: signerKey, canInitiate: true, canVote: true, canExecute: true),
            SquadMember(pubkey: signerKey, canInitiate: true, canVote: true, canExecute: true)
        ]
        XCTAssertThrowsError(try SquadsService.validateConfigChange(
            detail: detail,
            desiredMembers: desired,
            newThreshold: 1,
            newTimeLockSeconds: 0,
            newRentCollector: nil
        )) { error in
            guard case ConfigChangeError.contradictoryEdit = error else {
                return XCTFail("expected contradictoryEdit, got \(error)")
            }
        }
    }

    func testInvalidMemberAddressThrows() {
        let detail = makeTwoOfTwo()
        let desired = [
            SquadMember(pubkey: signerKey, canInitiate: true, canVote: true, canExecute: true),
            SquadMember(pubkey: "not-a-valid-address", canInitiate: true, canVote: true, canExecute: true)
        ]
        XCTAssertThrowsError(try SquadsService.validateConfigChange(
            detail: detail,
            desiredMembers: desired,
            newThreshold: 1,
            newTimeLockSeconds: 0,
            newRentCollector: nil
        )) { error in
            guard case ConfigChangeError.invalidMemberAddress = error else {
                return XCTFail("expected invalidMemberAddress, got \(error)")
            }
        }
    }

    func testTimeLockOverMaxThrows() {
        let detail = makeTwoOfTwo()
        XCTAssertThrowsError(try SquadsService.validateConfigChange(
            detail: detail,
            desiredMembers: detail.members,
            newThreshold: detail.threshold,
            newTimeLockSeconds: 7_776_001,
            newRentCollector: detail.rentCollector
        )) { error in
            guard case ConfigChangeError.timeLockOutOfRange = error else {
                return XCTFail("expected timeLockOutOfRange, got \(error)")
            }
        }
    }

    func testTimeLockChangeAloneIsValid() {
        let detail = makeTwoOfTwo()
        XCTAssertNoThrow(try SquadsService.validateConfigChange(
            detail: detail,
            desiredMembers: detail.members,
            newThreshold: detail.threshold,
            newTimeLockSeconds: 86400,
            newRentCollector: detail.rentCollector
        ))
    }

    func testNoProposerThrows() {
        let detail = makeTwoOfTwo()
        // Both members can vote and execute but cannot initiate (propose).
        let desired = [
            SquadMember(pubkey: signerKey, canInitiate: false, canVote: true, canExecute: true),
            SquadMember(pubkey: otherKey, canInitiate: false, canVote: true, canExecute: true)
        ]
        XCTAssertThrowsError(try SquadsService.validateConfigChange(
            detail: detail,
            desiredMembers: desired,
            newThreshold: 1,
            newTimeLockSeconds: detail.timeLockSeconds,
            newRentCollector: detail.rentCollector
        )) { error in
            guard case ConfigChangeError.thresholdOutOfRange = error else {
                return XCTFail("expected thresholdOutOfRange, got \(error)")
            }
        }
    }

    func testNoExecutorThrows() {
        let detail = makeTwoOfTwo()
        // Both members can initiate and vote but cannot execute.
        let desired = [
            SquadMember(pubkey: signerKey, canInitiate: true, canVote: true, canExecute: false),
            SquadMember(pubkey: otherKey, canInitiate: true, canVote: true, canExecute: false)
        ]
        XCTAssertThrowsError(try SquadsService.validateConfigChange(
            detail: detail,
            desiredMembers: desired,
            newThreshold: 1,
            newTimeLockSeconds: detail.timeLockSeconds,
            newRentCollector: detail.rentCollector
        )) { error in
            guard case ConfigChangeError.thresholdOutOfRange = error else {
                return XCTFail("expected thresholdOutOfRange, got \(error)")
            }
        }
    }
}
