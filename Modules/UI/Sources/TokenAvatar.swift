import Indexer
import SwiftUI

struct TokenAvatar: View {
    var localImageName: String?
    var remoteURL: URL?
    var symbol: String?
    var seed: String = ""

    var body: some View {
        ZStack {
            if let localImageName {
                Image(localImageName, bundle: .main)
                    .resizable()
                    .scaledToFill()
            } else if let remoteURL {
                AsyncImage(url: remoteURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty, .failure:
                        monogram
                    @unknown default:
                        monogram
                    }
                }
            } else {
                monogram
            }
        }
        .frame(width: 40, height: 40)
        .background(CosignTheme.surface2, in: .circle)
        .clipShape(.circle)
        .overlay {
            Circle().stroke(CosignTheme.line, lineWidth: 1)
        }
    }

    private var monogram: some View {
        TokenMonogram(symbol: symbol, seed: seed)
    }
}

/// Fallback token art: a generated monogram tile (symbol initial on a tint
/// derived deterministically from the mint), used when neither a curated
/// asset nor a registry image (DAS `imageURI`) is available.
struct TokenMonogram: View {
    var symbol: String?
    var seed: String = ""

    var body: some View {
        ZStack {
            tint.opacity(0.20)
            Text(initial)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var initial: String {
        let trimmed = (symbol ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.unicodeScalars.first(where: CharacterSet.alphanumerics.contains) else {
            return "?"
        }
        return String(first).uppercased()
    }

    private var tint: Color {
        guard !seed.isEmpty else {
            return CosignTheme.inkDim
        }
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in seed.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.55, brightness: 0.72)
    }
}

enum TokenArtwork {
    static let solAssetName = "TokenSOL"

    static func localAssetName(for asset: DASAsset) -> String? {
        switch asset.id {
        case "So11111111111111111111111111111111111111112":
            solAssetName
        case "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v":
            "TokenUSDC"
        case "jtojtomepa8beP8AuQc6eXt5FriJwfFMwQx2v2f9mCL":
            "TokenJTO"
        case "98sMhvDwXj1RQi5c5Mndm3vPe9cBqPrbLaufMXFNMh5g":
            "TokenHYPE"
        case "hntyVP6YFm1Hg25TN9WGLqM12b8TQmcknKrdu1oxWux":
            "TokenHNT"
        default:
            nil
        }
    }
}
