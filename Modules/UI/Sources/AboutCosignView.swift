import Provenance
import SwiftUI

enum AboutLinks {
    static let repository = URL(string: "https://github.com/hackshare/cosign")!
    static let privacy = URL(string: "https://cosign.hackshare.com/privacy")!
}

public struct AboutCosignView: View {
    @Environment(Coordinator.self) private var coordinator
    @Environment(\.openURL) private var openURL

    public init() {}

    public var body: some View {
        CosignScreen {
            CosignCompactPageHeader(title: CosignCopy.About.appName) { coordinator.pop() }

            VStack(alignment: .leading, spacing: 14) {
                CosignMark(size: 44)
                VStack(alignment: .leading, spacing: 6) {
                    Text(CosignCopy.About.appName)
                        .font(CosignTheme.FontStyle.display)
                        .foregroundStyle(CosignTheme.ink)
                    Text(CosignCopy.About.tagline)
                        .font(CosignTheme.FontStyle.caption)
                        .foregroundStyle(CosignTheme.inkDim)
                }
            }

            CosignCard {
                VStack(spacing: 0) {
                    CosignKeyValueRow(
                        label: CosignCopy.About.versionLabel,
                        value: bundle.version ?? CosignCopy.About.emptyValue
                    )
                    CosignKeyValueRow(
                        label: CosignCopy.About.buildLabel,
                        value: bundle.build ?? CosignCopy.About.emptyValue,
                        isLast: true
                    )
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                CosignSectionTitle(title: CosignCopy.About.linksSection)
                linkCard(
                    title: CosignCopy.About.sourceTitle,
                    subtitle: CosignCopy.About.sourceSubtitle,
                    url: AboutLinks.repository
                )
                linkCard(
                    title: CosignCopy.About.privacyTitle,
                    subtitle: CosignCopy.About.privacySubtitle,
                    url: AboutLinks.privacy
                )
            }
        }
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .cosignScreenIdentifier("screen.about")
        .cosignPage()
    }

    private var bundle: RunningBundle {
        RunningBundle.current()
    }

    private func linkCard(title: String, subtitle: String, url: URL) -> some View {
        CosignCard {
            CosignObjectRowButton(action: { openURL(url) }, label: {
                CosignNavigationRow(
                    title: title,
                    subtitle: subtitle,
                    systemImage: "arrow.up.forward.square"
                )
            })
        }
    }
}
