import CosignCore
import Indexer
import Testing
@testable import Squads
@testable import UI

struct DecodeProposalRequestBuildTests {
    @Test func mapsConfigActionRenamingTimeLock() {
        let swift = SquadConfigAction(
            memberKey: "M", canInitiate: true, canVote: false, canExecute: true,
            newThreshold: 2, newTimeLockSeconds: 3600, newRentCollector: "R",
            clearsRentCollector: false
        )
        let ffi = ConfigActionInfo(swift)
        #expect(ffi.memberKey == "M")
        #expect(ffi.newThreshold == 2)
        #expect(ffi.newTimeLock == 3600)
        #expect(ffi.clearsRentCollector == false)
    }

    @Test func mapsInstructionFields() {
        let swift = SquadDecodedInstruction(
            program: "11111111111111111111111111111111", kind: "raw", summary: "",
            accounts: ["a", "b"], rawDataHex: "0200", configAction: nil
        )
        let ffi = DecodedInstruction(swift)
        #expect(ffi.program == "11111111111111111111111111111111")
        #expect(ffi.accounts == ["a", "b"])
        #expect(ffi.rawDataHex == "0200")
        #expect(ffi.configAction == nil)
    }
}
