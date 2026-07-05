import Squads
import SwiftUI

private let devnetFaucetURL = URL(string: "https://faucet.solana.com")!

extension CreateSquadView {
    var wizardHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(CosignCopy.CreateSquad.eyebrow)
                    .font(CosignTheme.FontStyle.titleL)
                    .foregroundStyle(CosignTheme.ink)
                Spacer(minLength: 12)
                Text("\(step.index)/\(CreateSquadStep.allCases.count)")
                    .font(CosignTheme.FontStyle.mono)
                    .foregroundStyle(CosignTheme.inkFaint)
            }

            CosignStepProgress(
                currentStep: step.index,
                totalSteps: CreateSquadStep.allCases.count
            )

            VStack(alignment: .leading, spacing: 7) {
                Text(stepHeadline)
                    .font(CosignTheme.FontStyle.display)
                    .foregroundStyle(CosignTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(stepSubtitle)
                    .font(CosignTheme.FontStyle.body)
                    .foregroundStyle(CosignTheme.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    var stepContent: some View {
        switch step {
        case .funding:
            fundingStep
        case .members:
            membersStep
        case .threshold:
            thresholdStep
        case .review:
            reviewStep
        }
    }

    var fundingStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            CosignCard {
                CosignAddressBlock(
                    title: CosignCopy.CreateSquad.balanceLabel,
                    address: memberAddress,
                    accessibilityLabel: CosignCopy.CreateSquad.copyAddress
                )
                if let balance = balanceLamports {
                    Text(solAmount(balance))
                        .font(CosignTheme.FontStyle.titleM)
                        .foregroundStyle(CosignTheme.ink)
                        .padding(.top, 8)
                }
            }

            if isFunded {
                CosignInlineBanner(tone: .mint) {
                    Text(CosignCopy.CreateSquad.fundedEnough)
                }
            } else if airdropFailed {
                CosignInlineBanner(tone: .amber) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(CosignCopy.CreateSquad.airdropFailedTitle)
                            .font(CosignTheme.FontStyle.titleM)
                        Text(CosignCopy.CreateSquad.airdropFailedBody)
                            .font(CosignTheme.FontStyle.body)
                    }
                }
                Link(CosignCopy.CreateSquad.faucetLink, destination: devnetFaucetURL)
                    .font(CosignTheme.FontStyle.body)
                    .foregroundStyle(CosignTheme.accentDeep)
            } else if indexerEnvironment.supportsAirdrop {
                VStack(alignment: .leading, spacing: 8) {
                    Text(CosignCopy.CreateSquad.needDevnetSOL)
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.inkDim)
                    Button {
                        Task { await requestAirdrop() }
                    } label: {
                        if isAirdropping {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .tint(CosignTheme.ink)
                                Text(CosignCopy.CreateSquad.airdropWorking)
                            }
                        } else {
                            Text(CosignCopy.CreateSquad.getDevnetSOL)
                        }
                    }
                    .disabled(isAirdropping)
                    .buttonStyle(CosignButtonStyle(kind: .secondary))
                }
            } else {
                CosignInlineBanner(tone: .neutral) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let cost {
                            Text(CosignCopy.CreateSquad.mainnetNeedAmount(solQuantity(cost.total)))
                                .font(CosignTheme.FontStyle.titleM)
                                .foregroundStyle(CosignTheme.ink)
                        }
                        Text(CosignCopy.CreateSquad.mainnetFundInstruction)
                            .font(CosignTheme.FontStyle.body)
                    }
                }
            }

            if let cost {
                CosignCard {
                    HStack {
                        Text(CosignCopy.CreateSquad.costLabel)
                            .font(CosignTheme.FontStyle.body)
                            .foregroundStyle(CosignTheme.inkDim)
                        Spacer()
                        Text(CosignCopy.CreateSquad.estimatedTotal(solQuantity(cost.total)))
                            .font(CosignTheme.FontStyle.mono)
                            .foregroundStyle(CosignTheme.ink)
                    }
                }
            }
        }
    }

    var membersStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            CosignCard {
                VStack(alignment: .leading, spacing: 12) {
                    memberRow(
                        address: memberAddress,
                        label: CosignCopy.CreateSquad.youCreator,
                        canRemove: false,
                        pinned: true
                    )
                    ForEach(extraMembers, id: \.self) { member in
                        memberRow(address: member, label: cosignShortAddress(member), canRemove: true)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(CosignCopy.CreateSquad.addMemberPlaceholder.uppercased())
                    .font(CosignTheme.FontStyle.eyebrow)
                    .foregroundStyle(CosignTheme.inkFaint)
                TextField(CosignCopy.CreateSquad.addMemberPlaceholder, text: $newMember)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .cosignField()

                if let memberError {
                    CosignInlineBanner(tone: .red) {
                        Text(memberError)
                    }
                }

                Button {
                    addMember()
                } label: {
                    Text(CosignCopy.CreateSquad.addMember)
                }
                .buttonStyle(CosignButtonStyle(kind: .secondary))
            }
        }
    }

    var thresholdStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            CosignCard {
                if memberCount == 1 {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(CosignCopy.CreateSquad.soloThresholdTitle)
                                .font(CosignTheme.FontStyle.titleM)
                                .foregroundStyle(CosignTheme.ink)
                            Text(CosignCopy.CreateSquad.soloThresholdSubtitle)
                                .font(CosignTheme.FontStyle.caption)
                                .foregroundStyle(CosignTheme.inkDim)
                        }
                        Spacer()
                        Stepper("", value: $threshold, in: 1 ... 1)
                            .labelsHidden()
                            .disabled(true)
                            .opacity(0.5)
                    }
                } else {
                    Stepper(
                        value: $threshold,
                        in: 1 ... memberCount,
                        label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(CosignCopy.CreateSquad.thresholdSummary(threshold, of: memberCount))
                                    .font(CosignTheme.FontStyle.titleM)
                                    .foregroundStyle(CosignTheme.ink)
                                Text(CosignCopy.CreateSquad.memberCount(memberCount))
                                    .font(CosignTheme.FontStyle.caption)
                                    .foregroundStyle(CosignTheme.inkDim)
                            }
                        }
                    )
                }
            }

            if memberCount == 1 {
                CosignInlineBanner(tone: .neutral) {
                    Text(CosignCopy.CreateSquad.soloThresholdExplainer)
                }
            }
        }
    }

    var reviewStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                CosignSectionTitle(title: CosignCopy.CreateSquad.configurationLabel)
                CosignCard {
                    VStack(alignment: .leading, spacing: 12) {
                        factRow(label: CosignCopy.CreateSquad.networkLabel, value: CosignCopy.CreateSquad.devnetValue)
                        factRow(
                            label: CosignCopy.CreateSquad.thresholdTitle,
                            value: CosignCopy.CreateSquad.thresholdSummary(threshold, of: memberCount)
                        )
                        factRow(
                            label: CosignCopy.CreateSquad.membersTitle,
                            value: CosignCopy.CreateSquad.memberCount(memberCount)
                        )
                    }
                }
            }

            if let cost {
                CosignCard {
                    VStack(alignment: .leading, spacing: 8) {
                        CosignSectionTitle(title: CosignCopy.CreateSquad.costLabel)
                        costRow(label: CosignCopy.CreateSquad.costNetworkFee, lamports: cost.networkFee)
                        costRow(label: CosignCopy.CreateSquad.costRent, lamports: cost.rent)
                        costRow(label: CosignCopy.CreateSquad.costCreationFee, lamports: cost.creationFee)
                        Divider()
                            .overlay(CosignTheme.line)
                        costRow(label: CosignCopy.CreateSquad.costTotal, lamports: cost.total)
                    }
                }
            }

            if let createError {
                CosignInlineBanner(tone: .red) {
                    Text(createError)
                }
            }
        }
    }

    private func costRow(label: String, lamports: UInt64) -> some View {
        HStack {
            Text(label)
                .font(CosignTheme.FontStyle.body)
                .foregroundStyle(CosignTheme.inkDim)
            Spacer()
            HStack(spacing: 4) {
                Text(solQuantity(lamports))
                    .font(CosignTheme.FontStyle.mono)
                    .foregroundStyle(CosignTheme.ink)
                    .monospacedDigit()
                Text(CosignCopy.CreateSquad.solUnit)
                    .font(CosignTheme.FontStyle.mono)
                    .foregroundStyle(CosignTheme.inkFaint)
            }
        }
    }

    private func factRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(CosignTheme.FontStyle.body)
                .foregroundStyle(CosignTheme.inkDim)
            Spacer()
            Text(value)
                .font(CosignTheme.FontStyle.body)
                .foregroundStyle(CosignTheme.ink)
        }
    }

    private func memberRow(address: String, label: String, canRemove: Bool, pinned: Bool = false) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(CosignTheme.FontStyle.titleM)
                    .foregroundStyle(CosignTheme.ink)
                Text(cosignShortAddress(address))
                    .font(CosignTheme.FontStyle.monoSmall)
                    .foregroundStyle(CosignTheme.inkDim)
            }
            Spacer()
            if pinned {
                Text(CosignCopy.CreateSquad.pinnedTag)
                    .font(CosignTheme.FontStyle.eyebrow)
                    .foregroundStyle(CosignTheme.inkFaint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(CosignTheme.surface, in: .capsule)
            } else if canRemove {
                Button {
                    removeMember(address)
                } label: {
                    CosignGlyphView(glyph: .xmark, size: 14, color: CosignTheme.inkDim)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var stepHeadline: String {
        switch step {
        case .funding: CosignCopy.CreateSquad.fundingTitle
        case .members: CosignCopy.CreateSquad.membersTitle
        case .threshold: CosignCopy.CreateSquad.thresholdTitle
        case .review: CosignCopy.CreateSquad.reviewTitle
        }
    }

    private var stepSubtitle: String {
        switch step {
        case .funding: CosignCopy.CreateSquad.fundingBody
        case .members: CosignCopy.CreateSquad.membersBody
        case .threshold: CosignCopy.CreateSquad.thresholdBody
        case .review: CosignCopy.CreateSquad.thresholdSummary(threshold, of: memberCount)
        }
    }
}
