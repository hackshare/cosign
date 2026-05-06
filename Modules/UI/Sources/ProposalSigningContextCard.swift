import SwiftUI

struct ProposalSigningContextItem: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    var detail: String?
}

struct ProposalSigningContextCard: View {
    let items: [ProposalSigningContextItem]

    var body: some View {
        CosignCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ProposalSigningContextRow(
                        label: item.label,
                        value: item.value,
                        detail: item.detail,
                        isLast: index == items.count - 1
                    )
                }
            }
        }
    }
}

private struct ProposalSigningContextRow: View {
    let label: String
    let value: String
    var detail: String?
    var isLast = false

    var body: some View {
        CosignKeyValueRow(
            label: label,
            value: value,
            detail: detail,
            isLast: isLast
        )
    }
}
