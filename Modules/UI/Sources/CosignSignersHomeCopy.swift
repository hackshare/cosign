import Foundation

extension CosignCopy {
    enum SignerHome {
        static func signedHere(_ count: Int) -> String {
            String(localized: "\(count) signed here", bundle: .module)
        }

        static let approvedStatus = String(localized: "Approved", bundle: .module)

        static func awaitingMore(_ remaining: Int) -> String {
            String(localized: "awaiting \(remaining) more", bundle: .module)
        }
    }
}

extension CosignCopy.Signers {
    static let searchAccessibilityLabel = String(localized: "Search Signers", bundle: .module)

    static func homeSubtitle(signerCount: Int, squadCount: Int?) -> String {
        let signers = paddedCount(signerCount)
        guard let squadCount else {
            return countSubtitle(count: signerCount)
        }
        return String(
            localized: "\(signers) signer\(signerCount == 1 ? "" : "s") · \(squadCount) squad\(squadCount == 1 ? "" : "s")",
            bundle: .module
        )
    }

    static func proposalsAwaitingTitle(count: Int) -> String {
        String(localized: "\(count) proposal\(count == 1 ? "" : "s") awaiting you", bundle: .module)
    }

    static func proposalsAwaitingSubtitle(signerLabels: [String]) -> String {
        guard !signerLabels.isEmpty else {
            return String(localized: "Across your signers", bundle: .module)
        }
        return String(localized: "Across \(formattedNameList(signerLabels))", bundle: .module)
    }

    static func memberOfSquadsTitle(count: Int) -> String {
        String(localized: "Member of · \(count) squad\(count == 1 ? "" : "s")", bundle: .module)
    }

    static let pendingColumnTitle = String(localized: "Pending", bundle: .module)

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
            String(localized: "\(names[0]) and \(names[1])", bundle: .module)
        default:
            String(localized: "\(names[0]) and \(names.count - 1) more", bundle: .module)
        }
    }
}
