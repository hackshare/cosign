import XCTest
@testable import Squads

final class ConfigChangeSummaryTests: XCTestCase {
    private func member(
        _ key: String,
        initiate: Bool = true,
        vote: Bool = true,
        execute: Bool = true
    ) -> SquadMember {
        SquadMember(pubkey: key, canInitiate: initiate, canVote: vote, canExecute: execute)
    }

    private func makeDetail(members: [SquadMember], threshold: UInt16 = 2) -> SquadDetail {
        SquadDetail(
            address: "SQ",
            threshold: threshold,
            timeLockSeconds: 0,
            transactionIndex: 0,
            staleTransactionIndex: 0,
            members: members,
            vaults: []
        )
    }

    private func inst(_ kind: String, _ action: SquadConfigAction) -> SquadDecodedInstruction {
        SquadDecodedInstruction(program: "Squads", kind: kind, summary: "", rawDataHex: "", configAction: action)
    }

    func testRemoveAddSameKeyCollapsesToPermissionRow() {
        let squad = makeDetail(members: [member("A", initiate: false, vote: true, execute: false), member("B")])
        let rows = ConfigChangeSummary.build(detail: squad, instructions: [
            inst("remove_member", SquadConfigAction(memberKey: "A")),
            inst("add_member", SquadConfigAction(memberKey: "A", canInitiate: true, canVote: true, canExecute: true))
        ])
        XCTAssertEqual(rows.count, 1)
        guard case let .permission(address, old, new) = rows[0] else {
            return XCTFail("expected permission row")
        }
        XCTAssertEqual(address, "A")
        XCTAssertEqual(old, MemberPermissions(canInitiate: false, canVote: true, canExecute: false))
        XCTAssertEqual(new, MemberPermissions(canInitiate: true, canVote: true, canExecute: true))
    }

    func testLoneAddAndLoneRemoveStaySeparate() {
        let squad = makeDetail(members: [member("A"), member("B")])
        let rows = ConfigChangeSummary.build(detail: squad, instructions: [
            inst("remove_member", SquadConfigAction(memberKey: "B")),
            inst("add_member", SquadConfigAction(memberKey: "C", canInitiate: true, canVote: true, canExecute: true))
        ])
        XCTAssertTrue(rows.contains { if case let .add(addr, _) = $0 { addr == "C" } else { false } })
        XCTAssertTrue(rows.contains { if case let .remove(addr) = $0 { addr == "B" } else { false } })
        XCTAssertFalse(rows.contains { if case .permission = $0 { true } else { false } })
    }

    func testThresholdRowUsesVoterDenominators() {
        // Current: A,B,C all voters → 3 voters, threshold 2. Add D (voter), change threshold to 3.
        let squad = makeDetail(members: [member("A"), member("B"), member("C")], threshold: 2)
        let rows = ConfigChangeSummary.build(detail: squad, instructions: [
            inst("add_member", SquadConfigAction(memberKey: "D", canInitiate: true, canVote: true, canExecute: true)),
            inst("change_threshold", SquadConfigAction(newThreshold: 3))
        ])
        guard let row = rows.first(where: { if case .threshold = $0 { true } else { false } }),
              case let .threshold(oldValue, oldOf, newValue, newOf) = row
        else { return XCTFail("expected threshold row") }
        XCTAssertEqual(oldValue, 2); XCTAssertEqual(oldOf, 3)
        XCTAssertEqual(newValue, 3); XCTAssertEqual(newOf, 4)
    }

    func testRentCollectorClear() throws {
        let squad = SquadDetail(
            address: "SQ",
            threshold: 2,
            timeLockSeconds: 0,
            rentCollector: "OLD",
            transactionIndex: 0,
            staleTransactionIndex: 0,
            members: [member("A")],
            vaults: []
        )
        let rows = ConfigChangeSummary.build(detail: squad, instructions: [
            inst("set_rent_collector", SquadConfigAction(clearsRentCollector: true))
        ])
        guard case let .rentCollector(old, new) = try XCTUnwrap(
            rows.first(where: { if case .rentCollector = $0 { true } else { false } })
        ) else { return XCTFail("expected rentCollector row") }
        XCTAssertEqual(old, "OLD"); XCTAssertNil(new)
    }

    func testThresholdRowVoterDenominatorRemoveBranch() {
        // 3 voters, threshold 2; proposal removes one voter and keeps threshold 2 → denominator drops 3→2.
        let squad = makeDetail(members: [member("A"), member("B"), member("C")], threshold: 2)
        let rows = ConfigChangeSummary.build(detail: squad, instructions: [
            inst("remove_member", SquadConfigAction(memberKey: "C")),
            inst("change_threshold", SquadConfigAction(newThreshold: 2))
        ])
        guard let row = rows.first(where: { if case .threshold = $0 { true } else { false } }),
              case let .threshold(oldValue, oldOf, newValue, newOf) = row
        else { return XCTFail("expected threshold row") }
        XCTAssertEqual(oldValue, 2); XCTAssertEqual(oldOf, 3)
        XCTAssertEqual(newValue, 2); XCTAssertEqual(newOf, 2)
    }

    func testTimeLockRow() throws {
        let squad = SquadDetail(
            address: "SQ",
            threshold: 2,
            timeLockSeconds: 3600,
            transactionIndex: 0,
            staleTransactionIndex: 0,
            members: [member("A")],
            vaults: []
        )
        let rows = ConfigChangeSummary.build(detail: squad, instructions: [
            inst("set_time_lock", SquadConfigAction(newTimeLockSeconds: 7200))
        ])
        guard case let .timeLock(old, new) = try XCTUnwrap(
            rows.first(where: { if case .timeLock = $0 { true } else { false } })
        ) else { return XCTFail("expected timeLock row") }
        XCTAssertEqual(old, 3600); XCTAssertEqual(new, 7200)
    }

    func testRentCollectorSet() throws {
        let squad = SquadDetail(
            address: "SQ",
            threshold: 2,
            timeLockSeconds: 0,
            rentCollector: "OLDKEY",
            transactionIndex: 0,
            staleTransactionIndex: 0,
            members: [member("A")],
            vaults: []
        )
        let rows = ConfigChangeSummary.build(detail: squad, instructions: [
            inst("set_rent_collector", SquadConfigAction(newRentCollector: "NEWKEY", clearsRentCollector: false))
        ])
        guard case let .rentCollector(old, new) = try XCTUnwrap(
            rows.first(where: { if case .rentCollector = $0 { true } else { false } })
        ) else { return XCTFail("expected rentCollector row") }
        XCTAssertEqual(old, "OLDKEY"); XCTAssertEqual(new, "NEWKEY")
    }

    func testRowOrderIsPermissionThresholdAddRemove() {
        // A permission change, a lone add, a lone remove, and a threshold change together
        // must render in design order: permission, threshold, add, remove.
        let squad = makeDetail(members: [member("A"), member("B"), member("C")], threshold: 2)
        let rows = ConfigChangeSummary.build(detail: squad, instructions: [
            inst("remove_member", SquadConfigAction(memberKey: "A")),
            inst("add_member", SquadConfigAction(memberKey: "A", canInitiate: true, canVote: true, canExecute: true)),
            inst("add_member", SquadConfigAction(memberKey: "D", canInitiate: true, canVote: true, canExecute: true)),
            inst("remove_member", SquadConfigAction(memberKey: "B")),
            inst("change_threshold", SquadConfigAction(newThreshold: 3))
        ])
        XCTAssertEqual(rows.count, 4)
        guard case let .permission(permAddress, _, _) = rows[0], permAddress == "A" else {
            return XCTFail("row 0 should be the permission change for A")
        }
        guard case .threshold = rows[1] else { return XCTFail("row 1 should be the threshold change") }
        guard case let .add(addAddress, _) = rows[2], addAddress == "D" else {
            return XCTFail("row 2 should be the add of D")
        }
        guard case let .remove(removeAddress) = rows[3], removeAddress == "B" else {
            return XCTFail("row 3 should be the remove of B")
        }
    }

    func testSigningPowerLooserWhenVoterAddedWithoutThresholdChange() {
        // 3 voters, threshold 2. Add a voting member, no threshold change → 2 of 3 -> 2 of 4.
        let squad = makeDetail(members: [member("A"), member("B"), member("C")], threshold: 2)
        let rows = ConfigChangeSummary.build(detail: squad, instructions: [
            inst("add_member", SquadConfigAction(memberKey: "D", canInitiate: true, canVote: true, canExecute: true))
        ])
        guard case let .signingPower(threshold, oldOf, newOf) = rows.first(where: {
            if case .signingPower = $0 { true } else { false }
        }) else { return XCTFail("expected signingPower row") }
        XCTAssertEqual(threshold, 2); XCTAssertEqual(oldOf, 3); XCTAssertEqual(newOf, 4)
        XCTAssertFalse(rows.contains { if case .threshold = $0 { true } else { false } })
    }

    func testSigningPowerTighterWhenVoterRemovedWithoutThresholdChange() {
        let squad = makeDetail(members: [member("A"), member("B"), member("C")], threshold: 2)
        let rows = ConfigChangeSummary.build(detail: squad, instructions: [
            inst("remove_member", SquadConfigAction(memberKey: "C"))
        ])
        guard case let .signingPower(threshold, oldOf, newOf) = rows.first(where: {
            if case .signingPower = $0 { true } else { false }
        }) else { return XCTFail("expected signingPower row") }
        XCTAssertEqual(threshold, 2); XCTAssertEqual(oldOf, 3); XCTAssertEqual(newOf, 2)
    }

    func testSigningPowerSuppressedWhenThresholdChangePresent() {
        // Add a voter AND change threshold → the threshold row already reflects the denominator; no derived row.
        let squad = makeDetail(members: [member("A"), member("B"), member("C")], threshold: 2)
        let rows = ConfigChangeSummary.build(detail: squad, instructions: [
            inst("add_member", SquadConfigAction(memberKey: "D", canInitiate: true, canVote: true, canExecute: true)),
            inst("change_threshold", SquadConfigAction(newThreshold: 3))
        ])
        XCTAssertTrue(rows.contains { if case .threshold = $0 { true } else { false } })
        XCTAssertFalse(rows.contains { if case .signingPower = $0 { true } else { false } })
    }

    func testSigningPowerAbsentWhenVoterCountUnchanged() {
        // Promote a vote-only member to full: gains execute, keeps vote → voter count unchanged.
        let squad = makeDetail(
            members: [member("A", initiate: false, vote: true, execute: false), member("B"), member("C")],
            threshold: 2
        )
        let rows = ConfigChangeSummary.build(detail: squad, instructions: [
            inst("remove_member", SquadConfigAction(memberKey: "A")),
            inst("add_member", SquadConfigAction(memberKey: "A", canInitiate: true, canVote: true, canExecute: true))
        ])
        XCTAssertFalse(rows.contains { if case .signingPower = $0 { true } else { false } })
    }

    func testSigningPowerLooserWhenVoteGrantedToNonVoter() {
        // A can execute but not vote. Granting vote raises the voter pool 2 -> 3.
        let squad = makeDetail(
            members: [member("A", initiate: false, vote: false, execute: true), member("B"), member("C")],
            threshold: 2
        )
        let rows = ConfigChangeSummary.build(detail: squad, instructions: [
            inst("remove_member", SquadConfigAction(memberKey: "A")),
            inst("add_member", SquadConfigAction(memberKey: "A", canInitiate: false, canVote: true, canExecute: true))
        ])
        guard case let .signingPower(_, oldOf, newOf) = rows.first(where: {
            if case .signingPower = $0 { true } else { false }
        }) else { return XCTFail("expected signingPower row") }
        XCTAssertEqual(oldOf, 2); XCTAssertEqual(newOf, 3)
    }
}
