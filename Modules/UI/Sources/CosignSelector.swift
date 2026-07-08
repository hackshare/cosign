import SwiftUI

struct CosignSelectorOption<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    var subtitle: String?
    var detail: String?
    var glyph: CosignGlyph?
    var isEnabled = true
}

enum CosignSelectorSheetState {
    case loaded
    case loading
    case failed(message: String)
}

struct CosignSelectorField: View {
    let label: String?
    let title: String
    var subtitle: String?
    var detail: String?
    var isDisabled = false
    var isLoading = false
    var errorMessage: String?
    var accessibilityIdentifier: String?
    let action: () -> Void

    init(
        label: String? = nil,
        title: String,
        subtitle: String? = nil,
        detail: String? = nil,
        isDisabled: Bool = false,
        isLoading: Bool = false,
        errorMessage: String? = nil,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.isDisabled = isDisabled
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 8) {
                    if let label {
                        Text(label.uppercased())
                            .font(CosignTheme.FontStyle.eyebrow)
                            .foregroundStyle(CosignTheme.inkFaint)
                    }

                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(CosignTheme.FontStyle.titleM)
                                .foregroundStyle(isDisabled ? CosignTheme.inkFaint : CosignTheme.ink)
                                .lineLimit(1)
                            if let subtitle {
                                Text(subtitle)
                                    .font(CosignTheme.FontStyle.caption)
                                    .foregroundStyle(CosignTheme.inkFaint)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 8)

                        if let detail {
                            Text(detail)
                                .font(CosignTheme.FontStyle.monoSmall)
                                .foregroundStyle(CosignTheme.inkFaint)
                                .lineLimit(1)
                        }

                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 15, height: 15)
                        } else {
                            CosignGlyphView(
                                glyph: .chevronRight,
                                size: 15,
                                color: isDisabled ? CosignTheme.inkGhost : CosignTheme.inkFaint
                            )
                        }
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CosignTheme.surface2, in: .rect(cornerRadius: CosignTheme.Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: CosignTheme.Radius.control)
                        .stroke(borderColor, lineWidth: 1)
                }
                .contentShape(.rect(cornerRadius: CosignTheme.Radius.control))
            }
            .buttonStyle(.plain)
            .disabled(isDisabled || isLoading)
            .modifier(CosignOptionalAccessibilityIdentifier(identifier: accessibilityIdentifier))

            if let errorMessage {
                Text(errorMessage)
                    .font(CosignTheme.FontStyle.caption)
                    .foregroundStyle(CosignTheme.riskRed)
            }
        }
    }

    private var borderColor: Color {
        errorMessage == nil ? CosignTheme.line : CosignTheme.riskRed.opacity(0.5)
    }
}

struct CosignSelectorSheet<ID: Hashable>: View {
    let title: String
    var subtitle: String?
    let options: [CosignSelectorOption<ID>]
    var state: CosignSelectorSheetState = .loaded
    var onRetry: (() -> Void)?
    @Binding var selection: ID
    let onDismiss: () -> Void
    @State private var searchText = ""

    var body: some View {
        CosignScreen {
            header
            searchField

            selectorContent
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .accessibilityIdentifier("screen.selector-sheet")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule()
                .fill(CosignTheme.inkGhost)
                .frame(width: 42, height: 4)
                .frame(maxWidth: .infinity)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(CosignTheme.FontStyle.display)
                        .foregroundStyle(CosignTheme.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(CosignTheme.FontStyle.body)
                            .foregroundStyle(CosignTheme.inkDim)
                    }
                }

                Spacer(minLength: 12)
                CosignGlyphButton(glyph: .xmark, accessibilityLabel: CosignCopy.Common.close) {
                    onDismiss()
                }
            }
        }
    }

    @ViewBuilder
    private var searchField: some View {
        if showsSearch {
            CosignSearchField(placeholder: CosignCopy.Common.search, text: $searchText)
        }
    }

    @ViewBuilder
    private var selectorContent: some View {
        switch state {
        case .loading:
            selectorLoadingState
        case let .failed(message):
            selectorErrorState(message: message)
        case .loaded:
            if options.isEmpty {
                selectorEmptyState(
                    title: CosignCopy.Common.noSelectorOptionsTitle,
                    message: CosignCopy.Common.noSelectorOptionsMessage
                )
            } else if filteredOptions.isEmpty {
                selectorEmptyState(
                    title: CosignCopy.Common.noSelectorMatchesTitle,
                    message: CosignCopy.Common.noSelectorMatchesMessage
                )
            } else {
                optionsCard
            }
        }
    }

    private var optionsCard: some View {
        CosignCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(filteredOptions.enumerated()), id: \.element.id) { index, option in
                    Button {
                        guard option.isEnabled else {
                            return
                        }
                        selection = option.id
                        onDismiss()
                    } label: {
                        optionRow(option)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                option.id == selection ? CosignTheme.selectedWash : Color.clear,
                                in: .rect(cornerRadius: CosignTheme.Radius.medium)
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(!option.isEnabled)
                    .accessibilityIdentifier("selector-option-\(index)")

                    if index < filteredOptions.count - 1 {
                        Divider()
                            .overlay(CosignTheme.line)
                            .padding(.leading, 14)
                    }
                }
            }
        }
    }

    private var selectorLoadingState: some View {
        CosignCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(CosignCopy.Common.selectorLoadingTitle)
                    .font(CosignTheme.FontStyle.titleM)
                    .foregroundStyle(CosignTheme.ink)
                Text(CosignCopy.Common.selectorLoadingMessage)
                    .font(CosignTheme.FontStyle.body)
                    .foregroundStyle(CosignTheme.inkDim)
                CosignSkeletonBar(width: nil, height: 18)
                CosignSkeletonBar(width: 180, height: 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func selectorErrorState(message: String) -> some View {
        CosignCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(CosignCopy.Common.selectorErrorTitle)
                    .font(CosignTheme.FontStyle.titleM)
                    .foregroundStyle(CosignTheme.ink)
                Text(message)
                    .font(CosignTheme.FontStyle.body)
                    .foregroundStyle(CosignTheme.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
                if let onRetry {
                    Button(CosignCopy.Common.selectorRetryAction) {
                        onRetry()
                    }
                    .buttonStyle(CosignButtonStyle(kind: .secondary, fillsWidth: false))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func selectorEmptyState(title: String, message: String) -> some View {
        CosignCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(CosignTheme.FontStyle.titleM)
                    .foregroundStyle(CosignTheme.ink)
                Text(message)
                    .font(CosignTheme.FontStyle.body)
                    .foregroundStyle(CosignTheme.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func optionRow(_ option: CosignSelectorOption<ID>) -> some View {
        HStack(spacing: 12) {
            if let glyph = option.glyph {
                CosignGlyphView(glyph: glyph, size: 18, color: CosignTheme.accentDeep)
                    .frame(width: 36, height: 36)
                    .background(CosignTheme.accentWash, in: .rect(cornerRadius: CosignTheme.Radius.medium))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(option.title)
                    .font(CosignTheme.FontStyle.titleM)
                    .foregroundStyle(option.isEnabled ? CosignTheme.ink : CosignTheme.inkFaint)
                    .lineLimit(1)
                if let subtitle = option.subtitle {
                    Text(subtitle)
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.inkFaint)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let detail = option.detail {
                Text(detail)
                    .font(CosignTheme.FontStyle.monoSmall)
                    .foregroundStyle(CosignTheme.inkFaint)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if option.id == selection {
                CosignGlyphView(glyph: .check, size: 17, color: CosignTheme.accentDeep)
            }
        }
        .opacity(option.isEnabled ? 1 : 0.45)
    }

    private var showsSearch: Bool {
        if case .loaded = state {
            options.count >= 8
        } else {
            false
        }
    }

    private var filteredOptions: [CosignSelectorOption<ID>] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return options
        }
        return options.filter { option in
            option.matches(query)
        }
    }
}

private extension CosignSelectorOption {
    func matches(_ query: String) -> Bool {
        title.localizedCaseInsensitiveContains(query) ||
            subtitle?.localizedCaseInsensitiveContains(query) == true ||
            detail?.localizedCaseInsensitiveContains(query) == true
    }
}

private struct CosignOptionalAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}
