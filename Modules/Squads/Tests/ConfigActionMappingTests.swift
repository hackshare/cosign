import Indexer
import XCTest
@testable import Squads

final class ConfigActionMappingTests: XCTestCase {
    func testConfigActionMapsThroughRecord() {
        let record = ProposalInspectionInstruction(
            program: "Squads",
            kind: "add_member",
            summary: "Add member",
            accounts: [],
            rawDataHex: "",
            configAction: ProposalInspectionConfigAction(
                memberKey: "ABC",
                canInitiate: true,
                canVote: true,
                canExecute: false
            )
        )
        let decoded = SquadDecodedInstruction(record: record)
        XCTAssertEqual(decoded.configAction?.memberKey, "ABC")
        XCTAssertEqual(decoded.configAction?.canInitiate, true)
        XCTAssertEqual(decoded.configAction?.canExecute, false)
    }

    func testMissingConfigActionIsNil() {
        let record = ProposalInspectionInstruction(
            program: "System", kind: "transfer", summary: "x", accounts: [], rawDataHex: ""
        )
        XCTAssertNil(SquadDecodedInstruction(record: record).configAction)
    }
}
