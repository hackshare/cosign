import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

enum BuildVerificationLinks {
    static let repository = "https://github.com/hackshare/cosign"

    static func release(tag: String?) -> URL {
        if let tag, let url = URL(string: "\(repository)/releases/tag/\(tag)") {
            return url
        }
        return URL(string: "\(repository)/releases") ?? URL(string: repository)!
    }
}

struct BuildStatusBlock<Icon: View>: View {
    let title: String
    let subtitle: String
    let titleColor: Color
    let background: Color
    let border: Color
    let circle: Color
    @ViewBuilder let icon: Icon

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(circle)
                icon
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(CosignTheme.FontStyle.titleM)
                    .foregroundStyle(titleColor)
                Text(subtitle)
                    .font(CosignTheme.FontStyle.caption)
                    .foregroundStyle(CosignTheme.inkDim)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: .rect(cornerRadius: CosignTheme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: CosignTheme.Radius.card)
                .stroke(border, lineWidth: 1)
        }
    }
}

struct BuildRowsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CosignTheme.surface, in: .rect(cornerRadius: CosignTheme.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: CosignTheme.Radius.card)
                    .stroke(CosignTheme.line, lineWidth: 1)
            }
            .clipShape(.rect(cornerRadius: CosignTheme.Radius.card))
    }
}

struct BuildFactRow: View {
    let label: String
    let value: String
    var valueColor: Color = CosignTheme.ink
    var isMono = true
    var marker: String?
    var markerColor: Color = CosignTheme.mint
    var labelColor: Color = CosignTheme.inkFaint
    var background: Color = .clear
    var isLast = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text(label.uppercased())
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(labelColor)
                    .frame(width: 84, alignment: .leading)

                Text(value)
                    .font(valueFont)
                    .foregroundStyle(valueColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let marker {
                    Text(marker)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(markerColor)
                }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 16)
            .background(background)

            if !isLast {
                Divider().overlay(CosignTheme.line)
            }
        }
    }

    private var valueFont: Font {
        isMono
            ? .system(size: 13, weight: .regular, design: .monospaced)
            : .system(size: 13, weight: .medium, design: .rounded)
    }
}

struct BuildDiffRow: View {
    let label: String
    let claimValue: String
    let runningValue: String
    var isLast = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text(label.uppercased())
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(CosignTheme.riskRed)
                    .frame(width: 84, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text(CosignCopy.BuildVerification.claimValue(claimValue))
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(CosignTheme.riskRed)
                    Text(CosignCopy.BuildVerification.runningValue(runningValue))
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(CosignTheme.inkDim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 16)
            .background(CosignTheme.riskRed.opacity(0.06))

            if !isLast {
                Divider().overlay(CosignTheme.line)
            }
        }
    }
}

struct QRCodeView: View {
    let value: String
    var size: CGFloat = 66

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .padding(5)
        .background(CosignTheme.ink, in: .rect(cornerRadius: 9))
        .task(id: value) { image = Self.makeImage(value) }
    }

    private static func makeImage(_ value: String) -> UIImage? {
        let generator = CIFilter.qrCodeGenerator()
        generator.message = Data(value.utf8)
        generator.correctionLevel = "M"
        guard let coded = generator.outputImage else { return nil }

        let scaled = coded.transformed(by: CGAffineTransform(scaleX: 12, y: 12))

        let recolor = CIFilter.falseColor()
        recolor.inputImage = scaled
        recolor.color0 = CIColor(red: 8 / 255, green: 9 / 255, blue: 11 / 255)
        recolor.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let output = recolor.outputImage else { return nil }

        let context = CIContext()
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
