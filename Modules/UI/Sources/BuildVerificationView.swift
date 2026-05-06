import Provenance
import SwiftUI
import UIKit

public struct BuildVerificationView: View {
    @Environment(Coordinator.self) private var coordinator
    @Environment(\.openURL) private var openURL

    @State private var state: BuildProvenanceState?

    private let injectedState: BuildProvenanceState?

    public init(injectedState: BuildProvenanceState? = nil) {
        self.injectedState = injectedState
    }

    public var body: some View {
        CosignScreen {
            CosignCompactPageHeader(title: CosignCopy.BuildVerification.screenTitle) { coordinator.pop() }

            switch injectedState ?? state {
            case let .verified(claim):
                verifiedContent(claim)
            case let .developmentBuild(running):
                developmentContent(running)
            case let .failed(reason, claim, running):
                failedContent(reason: reason, claim: claim, running: running)
            case nil:
                EmptyView()
            }
        }
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .cosignScreenIdentifier("screen.build-verification")
        .cosignPage()
        .task {
            guard injectedState == nil else { return }
            state = BuildClaimVerifier.provenanceState()
        }
    }
}

// MARK: - Verified

private extension BuildVerificationView {
    @ViewBuilder
    func verifiedContent(_ verified: VerifiedBuildClaim) -> some View {
        BuildStatusBlock(
            title: CosignCopy.BuildVerification.verifiedTitle,
            subtitle: CosignCopy.BuildVerification.verifiedSubtitle,
            titleColor: CosignTheme.mint,
            background: CosignTheme.mint.opacity(0.08),
            border: CosignTheme.mint.opacity(0.22),
            circle: CosignTheme.mint.opacity(0.14)
        ) {
            CosignGlyphView(glyph: .check, size: 18, color: CosignTheme.mint)
        }

        section(CosignCopy.BuildVerification.signedClaimSection) {
            BuildRowsCard { signedClaimRows(verified.claim) }
        }

        section(CosignCopy.BuildVerification.fingerprintSection) {
            fingerprintCard(verified.fingerprint)
        }

        verifiedActions(verified)
    }

    @ViewBuilder
    private func signedClaimRows(_ claim: BuildClaim) -> some View {
        BuildFactRow(label: CosignCopy.BuildVerification.versionLabel, value: claim.version)
        BuildFactRow(label: CosignCopy.BuildVerification.buildLabel, value: claim.build)
        BuildFactRow(label: CosignCopy.BuildVerification.releaseLabel, value: claim.tag)
        BuildFactRow(
            label: CosignCopy.BuildVerification.commitLabel,
            value: String(claim.commitSha.prefix(8))
        )
        BuildFactRow(label: CosignCopy.BuildVerification.keyLabel, value: claim.keyId)
        BuildFactRow(
            label: CosignCopy.BuildVerification.toolchainLabel,
            value: CosignCopy.BuildVerification.toolchainValue(
                xcode: claim.toolchain.xcode,
                sdk: claim.toolchain.iphoneOSSDK
            ),
            isMono: false,
            isLast: true
        )
    }

    private func fingerprintCard(_ fingerprint: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(fingerprint)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(CosignTheme.inkDim)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            QRCodeView(value: fingerprint)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CosignTheme.surface2, in: .rect(cornerRadius: CosignTheme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: CosignTheme.Radius.card)
                .stroke(CosignTheme.line, lineWidth: 1)
        }
    }

    private func verifiedActions(_ verified: VerifiedBuildClaim) -> some View {
        VStack(spacing: 10) {
            Button(CosignCopy.BuildVerification.openReleaseButton) {
                openURL(BuildVerificationLinks.release(tag: verified.claim.tag))
            }
            .buttonStyle(CosignButtonStyle(kind: .accent))

            HStack(spacing: 10) {
                Button(CosignCopy.BuildVerification.copyFingerprintButton) {
                    copyToPasteboard(verified.fingerprint)
                }
                .buttonStyle(CosignButtonStyle(kind: .secondary))

                Button(CosignCopy.BuildVerification.copyClaimButton) {
                    copyToPasteboard(rawClaimJSON() ?? verified.fingerprint)
                }
                .buttonStyle(CosignButtonStyle(kind: .secondary))
            }
        }
    }

    // MARK: - Development

    @ViewBuilder
    private func developmentContent(_ running: RunningBundle) -> some View {
        BuildStatusBlock(
            title: CosignCopy.BuildVerification.developmentTitle,
            subtitle: CosignCopy.BuildVerification.developmentSubtitle,
            titleColor: CosignTheme.ink.opacity(0.82),
            background: CosignTheme.surface2,
            border: CosignTheme.line,
            circle: CosignTheme.surface3
        ) {
            Capsule()
                .fill(CosignTheme.inkFaint)
                .frame(width: 14, height: 2)
        }

        Text(CosignCopy.BuildVerification.developmentExplanation)
            .font(CosignTheme.FontStyle.caption)
            .foregroundStyle(CosignTheme.inkDim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cosignCard()

        section(CosignCopy.BuildVerification.runningBundleSection) {
            BuildRowsCard {
                BuildFactRow(
                    label: CosignCopy.BuildVerification.versionLabel,
                    value: running.version ?? CosignCopy.BuildVerification.emptyValue,
                    valueColor: CosignTheme.inkDim
                )
                BuildFactRow(
                    label: CosignCopy.BuildVerification.buildLabel,
                    value: running.build ?? CosignCopy.BuildVerification.emptyValue,
                    valueColor: CosignTheme.inkDim,
                    isLast: true
                )
            }
        }
    }

    // MARK: - Failed

    @ViewBuilder
    private func failedContent(
        reason: BuildProvenanceFailure,
        claim: BuildClaim?,
        running: RunningBundle
    ) -> some View {
        BuildStatusBlock(
            title: CosignCopy.BuildVerification.failedTitle,
            subtitle: CosignCopy.BuildVerification.reasonLabel(reason),
            titleColor: CosignTheme.riskRed,
            background: CosignTheme.riskRed.opacity(0.09),
            border: CosignTheme.riskRed.opacity(0.24),
            circle: CosignTheme.riskRed.opacity(0.14)
        ) {
            CosignGlyphView(glyph: .warning, size: 18, color: CosignTheme.riskRed)
        }

        reasonCard(reason)

        if let claim {
            section(CosignCopy.BuildVerification.claimVsRunningSection) {
                BuildRowsCard {
                    failedClaimRows(reason: reason, claim: claim, running: running)
                }
            }
        }

        failedActions(claim: claim)
    }

    private func reasonCard(_ reason: BuildProvenanceFailure) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(CosignCopy.BuildVerification.reasonEyebrow.uppercased())
                .font(CosignTheme.FontStyle.eyebrow)
                .foregroundStyle(CosignTheme.riskRed)
            Text(CosignCopy.BuildVerification.reasonDetail(reason))
                .font(CosignTheme.FontStyle.body)
                .foregroundStyle(CosignTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(CosignTheme.surface, in: .rect(cornerRadius: CosignTheme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: CosignTheme.Radius.card)
                .stroke(CosignTheme.riskRed.opacity(0.20), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func failedClaimRows(
        reason: BuildProvenanceFailure,
        claim: BuildClaim,
        running: RunningBundle
    ) -> some View {
        if reason == .invalidSignature {
            BuildFactRow(
                label: CosignCopy.BuildVerification.signatureLabel,
                value: CosignCopy.BuildVerification.signatureUntrustedValue,
                valueColor: CosignTheme.riskRed,
                isMono: false,
                labelColor: CosignTheme.riskRed,
                background: CosignTheme.riskRed.opacity(0.06)
            )
        }
        comparisonRow(
            label: CosignCopy.BuildVerification.versionLabel,
            value: claim.version,
            running: running.version,
            mismatched: reason == .versionMismatch
        )
        comparisonRow(
            label: CosignCopy.BuildVerification.buildLabel,
            value: claim.build,
            running: running.build,
            mismatched: reason == .buildMismatch
        )
        BuildFactRow(
            label: CosignCopy.BuildVerification.commitLabel,
            value: String(claim.commitSha.prefix(8))
        )
        keyRow(keyId: claim.keyId, untrusted: reason == .unknownKey)
    }

    @ViewBuilder
    private func comparisonRow(label: String, value: String, running: String?, mismatched: Bool) -> some View {
        if mismatched {
            BuildDiffRow(
                label: label,
                claimValue: value,
                runningValue: running ?? CosignCopy.BuildVerification.emptyValue
            )
        } else {
            BuildFactRow(label: label, value: value, marker: CosignCopy.BuildVerification.matchMarker)
        }
    }

    private func keyRow(keyId: String, untrusted: Bool) -> some View {
        BuildFactRow(
            label: CosignCopy.BuildVerification.keyLabel,
            value: keyId,
            valueColor: untrusted ? CosignTheme.riskRed : CosignTheme.ink,
            marker: untrusted
                ? CosignCopy.BuildVerification.untrustedMarker
                : CosignCopy.BuildVerification.trustedMarker,
            markerColor: untrusted ? CosignTheme.riskRed : CosignTheme.mint,
            labelColor: untrusted ? CosignTheme.riskRed : CosignTheme.inkFaint,
            background: untrusted ? CosignTheme.riskRed.opacity(0.06) : .clear,
            isLast: true
        )
    }

    private func failedActions(claim: BuildClaim?) -> some View {
        VStack(spacing: 10) {
            Button(CosignCopy.BuildVerification.openReleaseButton) {
                openURL(BuildVerificationLinks.release(tag: claim?.tag))
            }
            .buttonStyle(CosignButtonStyle(kind: .accent))

            Button(CosignCopy.BuildVerification.copyClaimJSONButton) {
                copyToPasteboard(rawClaimJSON() ?? "")
            }
            .buttonStyle(CosignButtonStyle(kind: .secondary))
        }
    }

    // MARK: - Helpers

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CosignSectionTitle(title: title)
            content()
        }
    }

    private func copyToPasteboard(_ value: String) {
        UIPasteboard.general.string = value
    }

    private func rawClaimJSON() -> String? {
        guard let url = Bundle.main.url(forResource: "BuildClaim", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

#if DEBUG
#Preview("Verified") {
    BuildVerificationView(injectedState: BuildProvenanceFixtures.verified)
        .environment(Coordinator())
        .preferredColorScheme(.dark)
}

#Preview("Failed") {
    BuildVerificationView(injectedState: BuildProvenanceFixtures.failedBuildMismatch)
        .environment(Coordinator())
        .preferredColorScheme(.dark)
}

#Preview("Development") {
    BuildVerificationView(injectedState: BuildProvenanceFixtures.development)
        .environment(Coordinator())
        .preferredColorScheme(.dark)
}
#endif
