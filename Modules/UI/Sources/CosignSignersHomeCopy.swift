extension CosignCopy.Signers {
    static let searchAccessibilityLabel = "Search Signers"

    static func homeSubtitle(signerCount: Int, squadCount: Int?) -> String {
        let signers = paddedCount(signerCount)
        guard let squadCount else {
            return countSubtitle(count: signerCount)
        }
        return "\(signers) signer\(signerCount == 1 ? "" : "s") · \(squadCount) squad\(squadCount == 1 ? "" : "s")"
    }

    static func proposalsAwaitingTitle(count: Int) -> String {
        "\(count) proposal\(count == 1 ? "" : "s") awaiting you"
    }

    static func proposalsAwaitingSubtitle(signerLabels: [String]) -> String {
        guard !signerLabels.isEmpty else {
            return "Across your signers"
        }
        return "Across \(formattedNameList(signerLabels))"
    }

    static func memberOfSquadsTitle(count: Int) -> String {
        "Member of · \(count) squad\(count == 1 ? "" : "s")"
    }

    static let pendingColumnTitle = "Pending"

    private static func paddedCount(_ count: Int) -> String {
        count < 10 ? "0\(count)" : "\(count)"
    }

    private static func formattedNameList(_ names: [String]) -> String {
        switch names.count {
        case 0:
            ""
        case 1:
            names[0]
        case 2:
            "\(names[0]) and \(names[1])"
        default:
            "\(names[0]) and \(names.count - 1) more"
        }
    }
}
