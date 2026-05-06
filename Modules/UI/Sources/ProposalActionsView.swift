import Core
import Foundation
import Indexer
import Signers
import Squads
import SwiftUI

struct ProposalActionSigner: Identifiable {
    let id: UUID
    let label: String
    let type: SignerType
    let pubkey: Pubkey
    let address: String
    let storage: ProposalActionSignerStorage
    var backedUp = true
}

enum ProposalActionSignerStorage: Equatable {
    case hotWallet(keychainAccount: String)
    case ledger
    case yubikey
}

struct ProposalSigningRequest: Identifiable {
    let id = UUID()
    let action: SquadProposalAction
    let signer: ProposalActionSigner
    let inspectionAction: RelayInspectionAction?
}

struct ProposalActionsSection: View {
    let proposal: SquadProposalDetail
    let signers: [ProposalActionSigner]
    @Binding var selectedSignerID: UUID?
    let squadMembers: [SquadMember]
    let isSubmittingAction: Bool
    var showsActionButtons = true
    var onConnectSigner: (() -> Void)?
    let onSelectAction: (SquadProposalAction, ProposalActionSigner) -> Void
    @State private var showsSignerSelector = false

    var body: some View {
        if proposal.canBeActedOn {
            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(title: CosignCopy.ProposalActions.sectionTitle)
                CosignCard {
                    content
                }
            }
            .sheet(isPresented: $showsSignerSelector) {
                signerSelectorSheet
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if signers.isEmpty {
            ProposalPermissionBanner(
                systemImage: "plus",
                title: CosignCopy.ProposalActions.noLocalSignerTitle,
                message: CosignCopy.ProposalActions.noLocalSignerMessage,
                tone: .amber,
                actionTitle: onConnectSigner == nil ? nil : CosignCopy.ProposalActions.connectSignerTitle,
                action: onConnectSigner
            )
        } else if let selectedSigner {
            CosignSelectorField(
                label: CosignCopy.ProposalActions.signerLabel,
                title: selectedSigner.label,
                subtitle: selectedSigner.type.displayName,
                detail: cosignShortAddress(selectedSigner.address)
            ) {
                showsSignerSelector = true
            }

            if showsActionButtons {
                CosignAddressBlock(
                    title: CosignCopy.ProposalActions.selectedSignerTitle,
                    address: selectedSigner.address,
                    accessibilityLabel: CosignCopy.ProposalActions.copySelectedSignerAccessibilityLabel()
                )
            }

            signerActions(for: selectedSigner)
        }
    }

    private var signerSelectorSheet: some View {
        CosignSelectorSheet(
            title: CosignCopy.ProposalActions.selectSignerTitle,
            subtitle: CosignCopy.ProposalActions.selectSignerSubtitle,
            options: signers.map { signer in
                CosignSelectorOption(
                    id: signer.id,
                    title: signer.label,
                    subtitle: signer.type.displayName,
                    detail: cosignShortAddress(signer.address),
                    glyph: .key
                )
            },
            selection: signerIDSelection,
            onDismiss: { showsSignerSelector = false }
        )
    }

    @ViewBuilder
    private func signerActions(for signer: ProposalActionSigner) -> some View {
        if let member = member(for: signer) {
            let actions = availableProposalActions(for: proposal, member: member)
            if actions.isEmpty {
                ProposalPermissionBanner(
                    systemImage: "lock",
                    title: CosignCopy.ProposalActions.permissionTitle(for: proposal, member: member),
                    message: proposalActionUnavailableMessage(for: proposal, member: member)
                        ?? CosignCopy.ProposalActions.noActionFallbackMessage,
                    tone: .neutral
                )
            } else {
                if showsActionButtons {
                    VStack(spacing: 8) {
                        ForEach(actions) { action in
                            Button {
                                onSelectAction(action, signer)
                            } label: {
                                ProposalActionButtonLabel(action: action)
                            }
                            .buttonStyle(CosignButtonStyle(
                                kind: buttonKind(for: action, allActions: actions),
                                height: actions.count > 1 ? CosignButtonHeight.stacked : CosignButtonHeight.primary
                            ))
                            .disabled(isSubmittingAction)
                            .accessibilityIdentifier("proposal-action-\(action.rawValue)")
                        }
                    }
                }
            }
        } else {
            ProposalPermissionBanner(
                systemImage: "lock",
                title: CosignCopy.ProposalActions.noMemberTitle,
                message: CosignCopy.ProposalActions.noMemberMessage,
                tone: .neutral
            )
        }
    }

    private var selectedSigner: ProposalActionSigner? {
        if let selectedSignerID, let signer = signers.first(where: { $0.id == selectedSignerID }) {
            return signer
        }
        return signers.first { signer in
            guard let member = member(for: signer) else {
                return false
            }
            return !availableProposalActions(for: proposal, member: member).isEmpty
        } ?? signers.first
    }

    private var signerIDSelection: Binding<UUID> {
        Binding(
            get: { selectedSigner?.id ?? signers.first?.id ?? UUID() },
            set: { selectedSignerID = $0 }
        )
    }

    private func member(for signer: ProposalActionSigner) -> SquadMember? {
        squadMembers.first { $0.pubkey == signer.address }
    }

    private func buttonKind(
        for action: SquadProposalAction,
        allActions: [SquadProposalAction]
    ) -> CosignButtonKind {
        switch action {
        case .approveAndExecute, .execute:
            .accent
        case .approve:
            allActions.contains(.approveAndExecute) ? .secondary : .accent
        case .reject:
            .secondary
        case .cancel:
            .destructive
        }
    }
}

struct ProposalStickyActionFooter: View {
    let proposal: SquadProposalDetail
    let signers: [ProposalActionSigner]
    let selectedSignerID: UUID?
    let squadMembers: [SquadMember]
    let isSubmittingAction: Bool
    var isHighRisk = false
    let onSelectAction: (SquadProposalAction, ProposalActionSigner) -> Void
    @State private var showsSecondaryActions = false

    var body: some View {
        if let selectedSigner, selectedMember != nil, let primaryAction {
            HStack(spacing: 10) {
                actionButton(
                    primaryAction,
                    signer: selectedSigner,
                    showsFinalSignerNote: false,
                    height: secondaryActions.isEmpty ? CosignButtonHeight.primary : CosignButtonHeight.stacked
                )
                .layoutPriority(1)

                if !secondaryActions.isEmpty {
                    Button {
                        showsSecondaryActions = true
                    } label: {
                        ProposalMoreActionsButtonLabel()
                    }
                    .buttonStyle(CosignButtonStyle(kind: .secondary, height: CosignButtonHeight.stacked))
                    .frame(width: 98)
                    .disabled(isSubmittingAction)
                    .accessibilityIdentifier("proposal-sticky-action-more")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .background(CosignTheme.background)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(CosignTheme.line)
                    .frame(height: 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("proposal-sticky-actions")
            .sheet(isPresented: $showsSecondaryActions) {
                ProposalSecondaryActionsSheet(
                    actions: secondaryActions,
                    isSubmittingAction: isSubmittingAction,
                    onCancel: { showsSecondaryActions = false },
                    onSelectAction: { action in
                        showsSecondaryActions = false
                        onSelectAction(action, selectedSigner)
                    }
                )
            }
        }
    }

    private var selectedSigner: ProposalActionSigner? {
        if let selectedSignerID, let signer = signers.first(where: { $0.id == selectedSignerID }) {
            return signer
        }
        return signers.first { signer in
            guard let member = member(for: signer) else {
                return false
            }
            return !availableProposalActions(for: proposal, member: member).isEmpty
        }
    }

    private var selectedMember: SquadMember? {
        selectedSigner.flatMap { member(for: $0) }
    }

    private var availableActions: [SquadProposalAction] {
        guard let selectedMember else {
            return []
        }
        return availableProposalActions(for: proposal, member: selectedMember)
    }

    private var primaryAction: SquadProposalAction? {
        if availableActions.contains(.approveAndExecute) {
            return .approveAndExecute
        }
        if availableActions.contains(.execute) {
            return .execute
        }
        if availableActions.contains(.approve) {
            return .approve
        }
        return availableActions.first
    }

    private var secondaryActions: [SquadProposalAction] {
        availableActions.filter { $0 != primaryAction }
    }

    private func actionButton(
        _ action: SquadProposalAction,
        signer: ProposalActionSigner,
        showsFinalSignerNote: Bool = true,
        height: CGFloat = CosignButtonHeight.primary
    ) -> some View {
        Button {
            onSelectAction(action, signer)
        } label: {
            ProposalActionButtonLabel(
                action: action,
                showsFinalSignerNote: showsFinalSignerNote,
                isHighRisk: isHighRisk
            )
        }
        .buttonStyle(CosignButtonStyle(kind: buttonKind(for: action), height: height))
        .disabled(isSubmittingAction)
        .accessibilityIdentifier("proposal-sticky-action-\(action.rawValue)")
    }

    private func member(for signer: ProposalActionSigner) -> SquadMember? {
        squadMembers.first { $0.pubkey == signer.address }
    }

    private func buttonKind(for action: SquadProposalAction) -> CosignButtonKind {
        if isHighRisk, action == .approve || action == .approveAndExecute || action == .execute {
            return .destructive
        }
        switch action {
        case .approveAndExecute, .execute:
            return .accent
        case .approve:
            return availableActions.contains(.approveAndExecute) ? .secondary : .accent
        case .reject:
            return .secondary
        case .cancel:
            return .destructive
        }
    }
}

private struct ProposalPermissionBanner: View {
    let systemImage: String
    let title: String
    let message: String
    let tone: CosignBannerTone
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CosignGlyphView(
                glyph: CosignGlyph(systemName: systemImage) ?? .warning,
                size: 16,
                color: tone.color
            )
            .frame(width: 32, height: 32)
            .background(tone.color.opacity(0.12), in: .rect(cornerRadius: CosignTheme.Radius.medium))
            .overlay {
                RoundedRectangle(cornerRadius: CosignTheme.Radius.medium)
                    .stroke(tone.color.opacity(0.24), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(CosignTheme.FontStyle.body)
                        .foregroundStyle(CosignTheme.ink)
                    Text(message)
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(CosignButtonStyle(kind: .secondary, fillsWidth: false))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
