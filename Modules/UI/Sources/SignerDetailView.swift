import Core
import CosignCore
import Foundation
import Indexer
import Persistence
import Signers
import Squads
import SwiftData
import SwiftUI

public struct SignerDetailView: View {
    @Environment(Coordinator.self) private var coordinator
    @Environment(\.modelContext) private var context
    @Environment(\.squadsService) private var squadsService
    @Query(sort: \RegisteredSigner.createdAt, order: .forward)
    private var signers: [RegisteredSigner]

    private let signerID: UUID

    @State var yubiKeyTransport = YubiKeyTransportChoice.wired
    @State var isTesting = false
    @State var diagnosticStatusMessage: String?
    @State var diagnosticResult: SignerDiagnosticResult?
    @State private var pendingRemove = false
    @State var showingReveal = false
    @State private var squadRows = [SignerHomeSquadRow]()
    @State private var isLoadingSquads = false

    public init(signerID: UUID) {
        self.signerID = signerID
    }

    public var body: some View {
        Group {
            if let signer {
                signerForm(signer)
            } else {
                CosignScreen {
                    CosignCompactPageHeader(title: CosignCopy.SignerDetail.navigationTitle) { coordinator.pop() }
                    CosignEmptyState(
                        title: CosignCopy.Signers.signerNotFoundTitle,
                        systemImage: "key.slash",
                        message: CosignCopy.Signers.signerNotFoundMessage
                    )
                }
            }
        }
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .cosignPage()
        .cosignScreenIdentifier("screen.signer-detail")
    }

    private var signer: RegisteredSigner? {
        signers.first { $0.id == signerID }
    }

    private func signerIdentityCard(_ signer: RegisteredSigner, address: String) -> some View {
        CosignCard(radius: CosignTheme.Radius.hero) {
            VStack(spacing: 0) {
                CosignKeyValueRow(
                    label: CosignCopy.SignerDetail.typeRowTitle,
                    value: signer.importedWithoutPhrase
                        ? CosignCopy.SignerDetail.importedTypeValue(base: CosignCopy.Signers.typeName(for: signer.type))
                        : CosignCopy.Signers.typeName(for: signer.type)
                )
                CosignKeyValueRow(
                    label: CosignCopy.SignerDetail.addedRowTitle,
                    value: signer.createdAt.formatted(date: .abbreviated, time: .shortened)
                )
                CosignAddressBlock(
                    title: CosignCopy.SignerDetail.memberAddressTitle,
                    address: address,
                    accessibilityLabel: CosignCopy.Signers.copySignerAddress
                )
                .padding(.top, 12)
            }
        }
    }

    private func signerForm(_ signer: RegisteredSigner) -> some View {
        let address = CosignCore.base58(signer.pubkey)

        return CosignScreen {
            CosignCompactPageHeader(title: CosignCopy.SignerDetail.navigationTitle) { coordinator.pop() }
            VStack(alignment: .leading, spacing: 8) {
                CosignSectionTitle(title: signerHeaderTitle(for: signer))
                Text(signer.label)
                    .font(CosignTheme.FontStyle.display)
                    .foregroundStyle(CosignTheme.ink)
            }

            signerIdentityCard(signer, address: address)

            if signer.type == .hotWallet {
                backupSection(signer)
            }

            if isLoadingSquads || !squadRows.isEmpty {
                squadsSection
            }

            if signer.type == .yubikey {
                yubiKeySection
            }

            diagnosticSection(signer)
            removeSection
        }
        .task(id: address) {
            await loadSquads(memberAddress: address)
        }
        .sheet(isPresented: $pendingRemove) {
            CosignDestructiveConfirmationSheet(
                title: CosignCopy.Signers.removeSignerTitle,
                message: removeMessage(for: signer),
                confirmTitle: CosignCopy.Signers.removeConfirmTitle(label: signer.label)
            ) {
                pendingRemove = false
            } onConfirm: {
                remove(signer)
            }
        }
        .sheet(isPresented: $showingReveal) {
            revealSheet(for: signer)
        }
    }

    @ViewBuilder
    private func revealSheet(for signer: RegisteredSigner) -> some View {
        if let account = signer.keychainItemRef {
            if signer.importedWithoutPhrase {
                SecretKeyRevealView(label: signer.label, keychainAccount: account) {
                    showingReveal = false
                }
            } else {
                RecoveryPhraseRevealView(label: signer.label, keychainAccount: account) {
                    showingReveal = false
                }
            }
        }
    }

    private var squadsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CosignSectionTitle(title: CosignCopy.Signers.memberOfSquadsTitle(count: squadRows.count))
            if squadRows.isEmpty {
                CosignLoadingCard()
            } else {
                CosignCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(squadRows.enumerated()), id: \.element.id) { index, row in
                            CosignObjectRowButton {
                                coordinator.go(to: .squadDetail(row.summary.address))
                            } label: {
                                SignerHomeSquadListRow(row: row)
                            }
                            .accessibilityIdentifier("signer-detail-squad-row-\(index)")

                            if index < squadRows.count - 1 {
                                Divider()
                                    .overlay(CosignTheme.line)
                                    .padding(.leading, 14)
                            }
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func loadSquads(memberAddress: String) async {
        guard !memberAddress.isEmpty, squadRows.isEmpty else {
            return
        }
        isLoadingSquads = true
        defer { isLoadingSquads = false }
        do {
            let summaries = try await squadsService.squads(forMember: memberAddress)
            var rows = [SignerHomeSquadRow]()
            for summary in summaries {
                let openCount = await openProposalCount(for: summary)
                rows.append(SignerHomeSquadRow(summary: summary, openProposalCount: openCount))
            }
            squadRows = rows
        } catch {
            squadRows = []
        }
    }

    private func openProposalCount(for summary: SquadSummary) async -> Int {
        guard let range = ProposalRange.recent(through: summary.transactionIndex, limit: 12) else {
            return 0
        }
        do {
            let proposals = try await squadsService.proposals(in: summary.address, range: range)
            return proposals.count { ["active", "approved"].contains($0.status.lowercased()) }
        } catch {
            return 0
        }
    }

    private var removeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CosignSectionTitle(title: CosignCopy.SignerDetail.deviceSectionTitle)
            Button {
                pendingRemove = true
            } label: {
                HStack(spacing: 10) {
                    CosignGlyphView(glyph: .xmark, size: 16, color: CosignTheme.riskRed)
                    Text(CosignCopy.SignerDetail.removeSignerTitle)
                    Spacer()
                }
                .font(CosignTheme.FontStyle.body)
                .foregroundStyle(CosignTheme.riskRed)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(CosignTheme.surface, in: .rect(cornerRadius: CosignTheme.Radius.card))
                .overlay {
                    RoundedRectangle(cornerRadius: CosignTheme.Radius.card)
                        .stroke(CosignTheme.riskRed.opacity(0.4), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func remove(_ signer: RegisteredSigner) {
        if signer.type == .hotWallet, let account = signer.keychainItemRef {
            try? HotWalletSigner.eraseFromKeychain(account: account)
        }
        context.delete(signer)
        try? context.save()
        pendingRemove = false
        coordinator.popToRoot()
    }

    private func removeMessage(for signer: RegisteredSigner) -> String {
        let base = signer.importedWithoutPhrase
            ? CosignCopy.SignerDetail.removeImportedMessage
            : CosignCopy.Signers.removeMessage(for: signer.type)
        guard !squadRows.isEmpty else { return base }
        return base + "\n\n" + CosignCopy.Signers.removeSquadMembershipNote(count: squadRows.count)
    }

    private func signerHeaderTitle(for signer: RegisteredSigner) -> String {
        CosignCopy.SignerDetail.headerTitle(for: signer.type)
    }
}
