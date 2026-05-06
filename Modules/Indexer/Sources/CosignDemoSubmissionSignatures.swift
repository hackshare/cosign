public enum CosignDemoSubmissionSignatureKind: Sendable {
    case propose
    case approve
    case approveAndExecute
    case execute
    case reject
    case cancel
}

public struct CosignDemoSubmissionSignature: Sendable {
    public let kind: CosignDemoSubmissionSignatureKind
    public let proposalIndex: UInt64
    public let offset: Int

    public static func signature(
        kind: CosignDemoSubmissionSignatureKind,
        proposalIndex: UInt64,
        offset: Int
    ) -> String {
        "\(seed(for: kind))\(proposalIndex)\(offset + 1)"
    }

    public static func parse(_ signature: String) -> CosignDemoSubmissionSignature? {
        for kind in kinds {
            let seed = seed(for: kind)
            guard signature.hasPrefix(seed) else {
                continue
            }

            let suffix = signature.dropFirst(seed.count)
            guard
                let offsetCharacter = suffix.last,
                let offset = Int(String(offsetCharacter)),
                offset > 0,
                let proposalIndex = UInt64(suffix.dropLast())
            else {
                return nil
            }

            return CosignDemoSubmissionSignature(
                kind: kind,
                proposalIndex: proposalIndex,
                offset: offset - 1
            )
        }

        return nil
    }

    private static let kinds: [CosignDemoSubmissionSignatureKind] = [
        .propose,
        .approve,
        .approveAndExecute,
        .execute,
        .reject,
        .cancel
    ]

    private static func seed(for kind: CosignDemoSubmissionSignatureKind) -> String {
        switch kind {
        case .propose:
            "6Pp9vpcUXwNJwGTqQox9KzfKXHU3zQ7CSewcxJBtUfRaaAj"
        case .approve:
            "38Hz4sbUsu5u6wV7hT4hLBvN8R5K7dRCMK3rQc6GFexyqPQW"
        case .approveAndExecute:
            "5X9KqmdR74aRYj4veWgRgSSvzh4qsUWY6zN6B73jFDwCqYQ"
        case .execute:
            "3z2dcecNAxQM3cPJn2vPuyxvR6b7QmwZeRbSPPz22WjKeTiv"
        case .reject:
            "2sxCsdvK4m3R98TmzjG6qztYh8LzuKDhxtiFBbQP39JHxka"
        case .cancel:
            "4u5qJrthLVcr6MUVmXnM11yBsdq7QgKbkSBM8bDffVYXGRt"
        }
    }
}
