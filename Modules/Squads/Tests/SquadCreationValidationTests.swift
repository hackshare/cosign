import XCTest
@testable import Squads

final class SquadCreationValidationTests: XCTestCase {
    // A valid base58 devnet pubkey (System program id is 32 zero bytes -> "111...").
    let creator = "So11111111111111111111111111111111111111112"
    let member = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"

    func testCreatorOnlyIsOneOfOne() throws {
        let extras = try SquadsService.validateSquadCreation(
            memberAddresses: [], threshold: 1, creator: creator
        )
        XCTAssertTrue(extras.isEmpty)
    }

    func testDedupesCreatorAndDuplicateMembers() throws {
        let extras = try SquadsService.validateSquadCreation(
            memberAddresses: [creator, member, member], threshold: 2, creator: creator
        )
        XCTAssertEqual(extras, [member]) // creator dropped, member once
    }

    func testThresholdOverMemberCountThrows() {
        XCTAssertThrowsError(try SquadsService.validateSquadCreation(
            memberAddresses: [member], threshold: 3, creator: creator
        )) { error in
            XCTAssertTrue(error is SquadCreationError)
        }
    }

    func testThresholdZeroThrows() {
        XCTAssertThrowsError(try SquadsService.validateSquadCreation(
            memberAddresses: [], threshold: 0, creator: creator
        )) { error in
            XCTAssertTrue(error is SquadCreationError)
        }
    }

    func testInvalidMemberAddressThrows() {
        XCTAssertThrowsError(try SquadsService.validateSquadCreation(
            memberAddresses: ["not-a-key"], threshold: 1, creator: creator
        )) { error in
            XCTAssertTrue(error is SquadCreationError)
        }
    }
}
