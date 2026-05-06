import Indexer
import SwiftUI

public struct NetworkSettingsView: View {
    @Environment(NetworkSettingsStore.self) private var networkSettings
    @Environment(Coordinator.self) private var coordinator

    @State private var endpointURLText = ""
    @State private var isEndpointURLVisible = false
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        CosignScreen {
            CosignCompactPageHeader(title: CosignCopy.Network.screenTitle) { coordinator.pop() }
            VStack(alignment: .leading, spacing: 8) {
                CosignSectionTitle(title: CosignCopy.Network.screenEyebrow)
                Text(CosignCopy.Network.screenTitle)
                    .font(CosignTheme.FontStyle.display)
                    .foregroundStyle(CosignTheme.ink)
            }

            CosignCard {
                Text(CosignCopy.Network.current.uppercased())
                    .font(CosignTheme.FontStyle.eyebrow)
                    .foregroundStyle(CosignTheme.inkFaint)
                Text(networkSettings.redactedRPCURLString)
                    .font(CosignTheme.FontStyle.mono)
                    .foregroundStyle(CosignTheme.ink)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .privacySensitive()
                    .padding(.top, 4)
            }

            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(title: CosignCopy.Network.endpointSection)
                CosignCard {
                    HStack(alignment: .firstTextBaseline) {
                        if isEndpointURLVisible {
                            TextField(CosignCopy.Network.endpointPlaceholder, text: $endpointURLText)
                        } else {
                            SecureField(CosignCopy.Network.endpointPlaceholder, text: $endpointURLText)
                        }

                        Button {
                            isEndpointURLVisible.toggle()
                        } label: {
                            Text(
                                isEndpointURLVisible
                                    ? CosignCopy.Network.hideEndpointURL
                                    : CosignCopy.Network.showEndpointURL
                            )
                            .font(CosignTheme.FontStyle.caption)
                            .foregroundStyle(CosignTheme.inkDim)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(
                            isEndpointURLVisible
                                ? CosignCopy.Network.hideEndpointURLAccessibilityLabel
                                : CosignCopy.Network.showEndpointURLAccessibilityLabel
                        )
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .font(CosignTheme.FontStyle.mono)
                    .privacySensitive()

                    Text(CosignCopy.Network.endpointHelp)
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.inkDim)
                        .padding(.top, 8)
                }
            }

            EndpointDetailsSection(
                title: CosignCopy.Network.savedEndpointSection,
                info: networkSettings.rpcURLInfo
            )

            VStack(spacing: 10) {
                Button(CosignCopy.Network.saveEndpointButton) {
                    saveEndpointURL()
                }
                .buttonStyle(CosignButtonStyle(kind: .primary))
                .disabled(!hasChanges)

                Button(CosignCopy.Network.resetToDevnetButton, role: .destructive) {
                    resetEndpointURL()
                }
                .buttonStyle(CosignButtonStyle(kind: .destructive))
                .disabled(networkSettings.rpcURL == NetworkSettingsStore.defaultRPCURL)
            }

            if let loadErrorMessage = networkSettings.loadErrorMessage {
                CosignEmptyState(
                    title: CosignCopy.Network.unableToLoadSavedEndpointTitle,
                    systemImage: "exclamationmark.triangle",
                    message: loadErrorMessage
                )
            }
        }
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .cosignScreenIdentifier("screen.network-settings")
        .cosignPage()
        .onAppear {
            loadURLText()
        }
        .sheet(isPresented: errorSheetBinding) {
            CosignNoticeSheet(
                title: CosignCopy.Network.settingsErrorTitle,
                message: errorMessage ?? "",
                tone: .red
            ) {
                errorMessage = nil
            }
        }
    }

    private var errorSheetBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var hasChanges: Bool {
        endpointURLText.trimmingCharacters(in: .whitespacesAndNewlines) != networkSettings.rpcURL.absoluteString
    }

    private func loadURLText() {
        endpointURLText = networkSettings.pendingRPCURLDraft?.rpcURL.absoluteString
            ?? networkSettings.rpcURL.absoluteString
    }

    private func saveEndpointURL() {
        do {
            try networkSettings.saveRPCURL(endpointURLText)
            endpointURLText = networkSettings.rpcURL.absoluteString
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetEndpointURL() {
        do {
            try networkSettings.resetRPCURL()
            endpointURLText = networkSettings.rpcURL.absoluteString
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
