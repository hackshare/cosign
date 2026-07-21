import Testing
@testable import UI

struct ActionObjectGatingTests {
    private func action(title: String, severity: ActionSeverity) -> ActionObject {
        ActionObject(
            title: title,
            subtitle: nil,
            severity: severity,
            confidence: .unknown,
            source: nil,
            roles: [],
            warnings: []
        )
    }

    @Test func genericHighActionIsNotReplaceable_gateKept() {
        let genericHigh = action(
            title: CosignCopy.ActionObject.reviewRawInstructionsBeforeSigningTitle,
            severity: .high
        )
        #expect(genericHigh.usesGenericReviewCopy)
        #expect(genericHigh.isReplaceableByLocalDecode == false)
    }

    @Test func genericNonHighActionIsReplaceable() {
        let routine = action(title: CosignCopy.ActionObject.reviewRawInstructionsBeforeSigningTitle, severity: .routine)
        let authority = action(
            title: CosignCopy.ActionObject.reviewUnknownExecutedInstructionsTitle,
            severity: .authority
        )
        #expect(routine.isReplaceableByLocalDecode)
        #expect(authority.isReplaceableByLocalDecode)
    }

    @Test func nonGenericActionIsNotReplaceable() {
        let swap = action(title: "swap(amount: 100)", severity: .routine)
        #expect(swap.usesGenericReviewCopy == false)
        #expect(swap.isReplaceableByLocalDecode == false)
    }
}
