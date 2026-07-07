import Core
import CosignCore
import Indexer
import Persistence
import Squads
import SwiftData
import SwiftUI

public struct ManageSquadConfigView: View {
    @Environment(Coordinator.self) var coordinator
    @Environment(\.cosignDemoMode) var demoMode
    @Environment(\.squadsService) var squadsService
    @Query(sort: \RegisteredSigner.createdAt, order: .forward) var registeredSigners: [RegisteredSigner]

    let squadAddress: String

    @State var detail: SquadDetail?
    @State var loadError: Bool = false
    @State var stagedRemovals: Set<String> = []
    @State var stagedAdditions: [String] = []
    @State var newMember: String = ""
    @State var memberError: String?
    @State var threshold: Int = 1
    @State var timeLockSeconds: UInt32 = 0
    @State var timeLockCustomExpanded = false
    @State var timeLockCustomValue: String = ""
    @State var timeLockCustomUnit: TimeLockUnit = .hours
    @State var isCreating = false
    @State var createError: String?
    @State private var footerHeight = CosignLayout.estimatedStickyFooterHeight

    public init(squadAddress: String) {
        self.squadAddress = squadAddress
    }

    public var body: some View {
        CosignScreen(bottomPadding: CosignLayout.screenBottomPadding(stickyFooterHeight: footerHeight)) {
            editorBody
        }
        .navigationTitle(CosignCopy.ManageSquad.screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
        .onChange(of: stagedRemovals) { clampThreshold() }
        .onChange(of: stagedAdditions) { clampThreshold() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            editorFooter
                .cosignMeasureHeight($footerHeight)
        }
        .accessibilityIdentifier("screen.manage-squad")
    }
}

enum TimeLockUnit: CaseIterable {
    case minutes, hours, days

    var seconds: UInt32 {
        switch self {
        case .minutes: 60
        case .hours: 3600
        case .days: 86400
        }
    }

    var label: String {
        switch self {
        case .minutes: CosignCopy.ManageSquad.timeLockUnitMinutes
        case .hours: CosignCopy.ManageSquad.timeLockUnitHours
        case .days: CosignCopy.ManageSquad.timeLockUnitDays
        }
    }
}

extension ManageSquadConfigView {
    // MARK: - Body

    @ViewBuilder
    private var editorBody: some View {
        if let detail {
            if !detail.isAutonomous {
                CosignInlineBanner(tone: .neutral) {
                    Text(CosignCopy.ManageSquad.controlledNote)
                }
            } else {
                membersSection(detail)
                editConsequenceBanner(for: detail)
                addMemberSection
                thresholdSection(detail)
                timeLockSection(detail)
                if let err = createError {
                    CosignInlineBanner(tone: .red) {
                        Text(err)
                    }
                }
            }
        } else if loadError {
            CosignEmptyState(
                title: CosignCopy.ManageSquad.loadErrorTitle,
                systemImage: "exclamationmark.triangle",
                message: CosignCopy.ManageSquad.loadErrorMessage,
                primaryActionTitle: CosignCopy.ManageSquad.loadErrorRetry,
                primaryAction: { Task { await load() } }
            )
        } else {
            CosignLoadingCard()
        }
    }

    // MARK: - Members section

    private func membersSection(_ detail: SquadDetail) -> some View {
        let diffText = stagedChangeDiff
        return VStack(alignment: .leading, spacing: 10) {
            CosignSectionTitle(
                title: CosignCopy.ManageSquad.membersSection,
                trailing: diffText.isEmpty ? nil : diffText
            )
            CosignCard {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(detail.members.enumerated()), id: \.element.id) { index, member in
                        existingMemberRow(member, index: index)
                    }
                    ForEach(Array(stagedAdditions.enumerated()), id: \.element) { index, address in
                        addedMemberRow(address, index: index)
                    }
                }
            }
        }
    }

    private func existingMemberRow(_ member: SquadMember, index: Int) -> some View {
        let staged = stagedRemovals.contains(member.pubkey)
        let isYou = currentSignerAddresses.contains(member.pubkey)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(cosignShortAddress(member.pubkey))
                        .font(CosignTheme.FontStyle.titleM)
                        .foregroundStyle(staged ? CosignTheme.inkFaint : CosignTheme.ink)
                        .strikethrough(staged, color: CosignTheme.inkFaint)
                    if isYou {
                        Text(CosignCopy.ManageSquad.youBadge)
                            .font(CosignTheme.FontStyle.eyebrow)
                            .foregroundStyle(CosignTheme.accentDeep)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(CosignTheme.accentWash, in: .capsule)
                    }
                }
                Text(cosignShortAddress(member.pubkey, prefix: 6, suffix: 6))
                    .font(CosignTheme.FontStyle.monoSmall)
                    .foregroundStyle(CosignTheme.inkDim)
            }
            Spacer()
            Button {
                toggleRemoval(member.pubkey)
            } label: {
                CosignGlyphView(
                    glyph: .xmark,
                    size: 14,
                    color: staged ? CosignTheme.accentDeep : CosignTheme.inkDim
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(isYou ? "manage-squad-remove-you" : "manage-squad-remove-\(index)")
        }
    }

    private func addedMemberRow(_ address: String, index: Int) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(cosignShortAddress(address))
                        .font(CosignTheme.FontStyle.titleM)
                        .foregroundStyle(CosignTheme.mint)
                    Text(CosignCopy.ManageSquad.addedBadge)
                        .font(CosignTheme.FontStyle.eyebrow)
                        .foregroundStyle(CosignTheme.mint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(CosignTheme.mintWash, in: .capsule)
                }
                Text(cosignShortAddress(address, prefix: 6, suffix: 6))
                    .font(CosignTheme.FontStyle.monoSmall)
                    .foregroundStyle(CosignTheme.inkDim)
            }
            Spacer()
            Button {
                removeStagedAddition(address)
            } label: {
                CosignGlyphView(glyph: .xmark, size: 14, color: CosignTheme.inkDim)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("manage-squad-remove-added-\(index)")
        }
    }

    /// One consequence banner at a time, escalated to the worst active state:
    /// a projected-invariant block (danger) supersedes the self-removal advisory
    /// (caution). The design system's banners never stack.
    @ViewBuilder
    private func editConsequenceBanner(for detail: SquadDetail) -> some View {
        if hasChanges, let validation = validationError {
            CosignInlineBanner(tone: .red) {
                Text(validation)
            }
            .accessibilityIdentifier("manage-squad-validation-banner")
        } else if hasSelfRemoval {
            let message = detail.threshold == 1
                ? CosignCopy.ManageSquad.selfRemovalSoloWarning
                : CosignCopy.ManageSquad.selfRemovalQuorumWarning
            CosignInlineBanner(tone: .amber) {
                Text(message)
            }
            .accessibilityIdentifier("manage-squad-self-removal-banner")
        }
    }

    // MARK: - Add member section

    private var addMemberSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CosignSectionTitle(title: CosignCopy.ManageSquad.addMemberSection)
            TextField(CosignCopy.ManageSquad.addMemberPlaceholder, text: $newMember)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { addMember() }
                .cosignField()
                .accessibilityIdentifier("manage-squad-new-member")
            if let err = memberError {
                CosignInlineBanner(tone: .red) {
                    Text(err)
                }
            }
            Button {
                addMember()
            } label: {
                Text(CosignCopy.ManageSquad.addMember)
            }
            .buttonStyle(CosignButtonStyle(kind: .secondary))
            .accessibilityIdentifier("manage-squad-add-member")
        }
    }

    // MARK: - Threshold section

    private func thresholdSection(_: SquadDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CosignSectionTitle(title: CosignCopy.ManageSquad.thresholdSection)
            CosignCard {
                Stepper(
                    value: $threshold,
                    in: 1 ... max(1, projectedVoterCount),
                    label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(CosignCopy.ManageSquad.thresholdSummary(threshold, of: projectedVoterCount))
                                .font(CosignTheme.FontStyle.titleM)
                                .foregroundStyle(CosignTheme.ink)
                            Text(CosignCopy.ManageSquad.voterCount(projectedVoterCount))
                                .font(CosignTheme.FontStyle.caption)
                                .foregroundStyle(CosignTheme.inkDim)
                        }
                    }
                )
            }
        }
    }

    // MARK: - Footer

    private var editorFooter: some View {
        CosignStickyFooter {
            if demoMode?.disablesNetworkWrites == true {
                Button {} label: {
                    HStack(spacing: 8) {
                        CosignGlyphView(glyph: .lock, size: 14, color: CosignTheme.inkFaint)
                        Text(CosignCopy.ManageSquad.createButton)
                    }
                }
                .disabled(true)
                .buttonStyle(CosignButtonStyle(kind: .secondary))
                .accessibilityIdentifier("manage-squad-create")
            } else if detail?.isAutonomous == true {
                Button {
                    Task { await create() }
                } label: {
                    if isCreating {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(CosignTheme.accentInk)
                            Text(CosignCopy.ManageSquad.creating)
                        }
                    } else {
                        Text(CosignCopy.ManageSquad.createButton)
                    }
                }
                .disabled(!canCreate || isCreating)
                .buttonStyle(CosignButtonStyle(kind: canCreate ? .accent : .secondary))
                .accessibilityIdentifier("manage-squad-create")
            }
        }
    }
}
