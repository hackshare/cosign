import Core
import CosignCore
import Persistence
import Signers
import SwiftData
import SwiftUI

struct AddHotWalletView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State var label = CosignCopy.HotWallet.defaultLabel
    @State var selectedSegment = 0
    @State var importWords: [String] = Array(repeating: "", count: 12)
    @State var secretKeyMode = false
    @State var secretKeyNumbers: [Int]?
    @State var secretKeyBytes: [UInt8] = []
    @State var secretKeyDerivedAddress: String?
    @State var secretKeyError: String?
    @State private var phase: Phase = .entry
    @State var generated: GeneratedWallet?
    @State var errorMessage: String?

    enum Phase {
        case entry
        case displayMnemonic
        case confirmMnemonic
        case done
    }

    struct GeneratedWallet {
        let signer: HotWalletSigner
        let mnemonic: String
    }

    init() {}

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .entry: entry
                case .displayMnemonic: displayMnemonic
                case .confirmMnemonic: confirmMnemonic
                case .done: doneView
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .cosignScreenIdentifier("screen.add-hot-wallet")
            .sheet(isPresented: errorSheetBinding) {
                CosignNoticeSheet(
                    title: CosignCopy.HotWallet.errorTitle,
                    message: errorMessage ?? "",
                    tone: .red
                ) {
                    errorMessage = nil
                }
            }
        }
    }

    private var errorSheetBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}

extension AddHotWalletView {
    @ViewBuilder
    var entry: some View {
        if selectedSegment == 0 {
            createScreen
        } else {
            importScreen
        }
    }

    private var createScreen: some View {
        CosignScreen {
            modeHeader(title: CosignCopy.HotWallet.newWalletTitle, headline: CosignCopy.HotWallet.createTitle)

            Button {
                generate()
            } label: {
                HStack(spacing: 10) {
                    CosignGlyphView(glyph: .key, size: 16, color: CosignTheme.accentInk)
                    Text(CosignCopy.HotWallet.generateMnemonicTitle)
                }
                .cosignPrimaryAction()
            }
            .buttonStyle(.plain)
            .disabled(isLabelEmpty)

            CosignInlineBanner {
                Text(CosignCopy.HotWallet.createInfoNote)
            }
        }
    }

    @ViewBuilder
    func modeHeader(title: String, headline: String) -> some View {
        CosignFlowHeader(title: title, onCancel: handleCancel)

        VStack(alignment: .leading, spacing: 8) {
            CosignSectionTitle(title: CosignCopy.HotWallet.walletSectionTitle)
            Text(headline)
                .font(CosignTheme.FontStyle.display)
                .foregroundStyle(CosignTheme.ink)
        }

        CosignSegmentedControl(
            labels: [CosignCopy.HotWallet.createSegment, CosignCopy.HotWallet.importSegment],
            selectedIndex: $selectedSegment
        )

        VStack(alignment: .leading, spacing: 10) {
            CosignSectionTitle(title: CosignCopy.HotWallet.labelSectionTitle)
            CosignCard {
                TextField(CosignCopy.HotWallet.defaultLabel, text: $label)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .cosignField()
            }
        }
    }

    var isLabelEmpty: Bool {
        label.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

extension AddHotWalletView {
    @ViewBuilder
    var displayMnemonic: some View {
        if let words = generated?.mnemonic.split(separator: " ").map(String.init) {
            CosignScreen {
                CosignFlowHeader(title: CosignCopy.HotWallet.backupTitle, onCancel: handleCancel)

                VStack(alignment: .leading, spacing: 8) {
                    CosignSectionTitle(title: CosignCopy.HotWallet.backupSectionTitle)
                    Text(CosignCopy.HotWallet.mnemonicTitle)
                        .font(CosignTheme.FontStyle.display)
                        .foregroundStyle(CosignTheme.ink)
                }

                VStack(spacing: 16) {
                    Text(CosignCopy.HotWallet.backupMessage)
                        .font(CosignTheme.FontStyle.body)
                        .foregroundStyle(CosignTheme.inkDim)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 110), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(Array(words.enumerated()), id: \.offset) { idx, word in
                            HStack(spacing: 4) {
                                Text(CosignCopy.HotWallet.wordOrdinal(idx + 1))
                                    .foregroundStyle(CosignTheme.inkFaint)
                                    .font(CosignTheme.FontStyle.caption)
                                    .frame(width: 22, alignment: .trailing)
                                Text(word)
                                    .font(CosignTheme.FontStyle.mono)
                                    .foregroundStyle(CosignTheme.ink)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(CosignTheme.surface, in: .rect(cornerRadius: CosignTheme.Radius.small))
                            .overlay {
                                RoundedRectangle(cornerRadius: CosignTheme.Radius.small)
                                    .stroke(CosignTheme.line, lineWidth: 1)
                            }
                        }
                    }
                    .privacySensitive()

                    Button {
                        phase = .confirmMnemonic
                    } label: {
                        Text(CosignCopy.HotWallet.writtenDownTitle)
                            .cosignPrimaryAction()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    var confirmMnemonic: some View {
        if let mnemonic = generated?.mnemonic {
            ConfirmMnemonicView(
                mnemonic: mnemonic,
                onConfirm: { saveAndAdvance() },
                onBack: { phase = .displayMnemonic }
            )
        }
    }

    var doneView: some View {
        CosignScreen {
            CosignSuccessReceipt(
                title: CosignCopy.HotWallet.walletAddedTitle,
                message: CosignCopy.HotWallet.walletAddedMessage,
                addressTitle: CosignCopy.HotWallet.memberAddressTitle,
                address: generated.map { CosignCore.base58($0.signer.pubkey) },
                copyAccessibilityLabel: CosignCopy.HotWallet.copyMemberAddress
            )
            Button(CosignCopy.HotWallet.doneButtonTitle) {
                dismiss()
            }
            .cosignPrimaryAction()
            .buttonStyle(.plain)
        }
    }
}

extension AddHotWalletView {
    func generate() {
        do {
            let result = try HotWalletSigner.generate(label: label)
            generated = GeneratedWallet(signer: result.signer, mnemonic: result.mnemonic)
            phase = .displayMnemonic
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func saveAndAdvance(importedWithoutPhrase: Bool = false) {
        guard let wallet = generated else { return }
        let registered = RegisteredSigner(
            label: wallet.signer.label,
            type: wallet.signer.type,
            pubkey: wallet.signer.pubkey,
            keychainItemRef: wallet.signer.keychainAccount,
            backedUp: true,
            backedUpAt: .now,
            importedWithoutPhrase: importedWithoutPhrase
        )
        context.insert(registered)
        do {
            try context.save()
            phase = .done
        } catch {
            errorMessage = CosignCopy.HotWallet.saveFailedMessage(error)
        }
    }

    func handleCancel() {
        if let signer = generated?.signer {
            try? signer.eraseFromKeychain()
        }
        dismiss()
    }
}
