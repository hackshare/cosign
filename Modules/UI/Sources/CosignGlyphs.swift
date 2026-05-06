// swiftlint:disable file_length
import SwiftUI

enum CosignGlyph: Equatable {
    case chevronRight
    case chevronLeft
    case plus
    case check
    case xmark
    case copy
    case external
    case settings
    case networkSettings
    case search
    case circle
    case wave
    case arrowUp
    case arrowDown
    case arrows
    case lock
    case faceID
    case shield
    case list
    case play
    case refresh
    case document
    case warning
    case tokenGrid
    case image
    case clock
    case key
    case sol
    case usdc
    case jito

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    init?(systemName: String) {
        switch systemName {
        case "chevron.right":
            self = .chevronRight
        case "chevron.left":
            self = .chevronLeft
        case "plus":
            self = .plus
        case "checkmark", "checkmark.circle", "checkmark.circle.fill":
            self = .check
        case "xmark", "xmark.circle":
            self = .xmark
        case "xmark.octagon", "xmark.octagon.fill", "key.slash", "person.slash":
            self = .xmark
        case "doc.on.doc":
            self = .copy
        case "arrow.up.forward.square":
            self = .external
        case "gearshape":
            self = .settings
        case "magnifyingglass", "doc.text.magnifyingglass":
            self = .search
        case "circle":
            self = .circle
        case "network", "wave.3.right":
            self = .wave
        case "arrow.up":
            self = .arrowUp
        case "arrow.down":
            self = .arrowDown
        case "arrow.clockwise":
            self = .refresh
        case "lock":
            self = .lock
        case "faceid":
            self = .faceID
        case "shield", "checkmark.seal", "checkmark.shield":
            self = .shield
        case "list.bullet":
            self = .list
        case "play.circle":
            self = .play
        case "doc.text", "curlybraces":
            self = .document
        case "exclamationmark.triangle":
            self = .warning
        case "circle.hexagongrid":
            self = .tokenGrid
        case "photo", "photo.on.rectangle":
            self = .image
        case "clock.arrow.circlepath":
            self = .clock
        case "key.horizontal":
            self = .key
        default:
            return nil
        }
    }
}

// swiftlint:disable type_body_length identifier_name
struct CosignGlyphView: View {
    let glyph: CosignGlyph
    var size: CGFloat = 18
    var color: Color = CosignTheme.ink

    var body: some View {
        ZStack {
            switch glyph {
            case .sol:
                tokenCircle(fill: Color(hex: 0x111111), text: "S", textColor: CosignTheme.accent)
            case .usdc:
                tokenCircle(fill: Color(hex: 0x2775CA), text: "$", textColor: .white)
            case .jito:
                tokenCircle(fill: Color(hex: 0xE8532B), text: "J", textColor: .white)
            case .settings:
                settingsGlyph
            case .networkSettings:
                networkSettingsGlyph
            case .copy:
                copyGlyph
            case .external:
                externalGlyph
            case .search:
                searchGlyph
            case .wave:
                waveGlyph
            case .faceID:
                faceIDGlyph
            case .shield:
                shieldGlyph
            case .tokenGrid:
                tokenGridGlyph
            case .image:
                imageGlyph
            case .key:
                keyGlyph
            case .document:
                documentGlyph
            case .warning:
                warningGlyph
            case .clock:
                clockGlyph
            case .lock:
                lockGlyph
            default:
                pathGlyph
            }
        }
        .frame(width: size, height: size)
    }

    private func tokenCircle(fill: Color, text: String, textColor: Color) -> some View {
        Circle()
            .fill(fill)
            .overlay {
                Text(text)
                    .font(.system(size: size * 0.48, weight: .bold, design: .rounded))
                    .foregroundStyle(textColor)
            }
    }

    private var pathGlyph: some View {
        Canvas { context, canvasSize in
            var path = Path()
            let w = canvasSize.width
            let h = canvasSize.height

            switch glyph {
            case .chevronRight:
                path.move(to: CGPoint(x: w * 0.35, y: h * 0.22))
                path.addLine(to: CGPoint(x: w * 0.65, y: h * 0.50))
                path.addLine(to: CGPoint(x: w * 0.35, y: h * 0.78))
            case .chevronLeft:
                path.move(to: CGPoint(x: w * 0.65, y: h * 0.22))
                path.addLine(to: CGPoint(x: w * 0.35, y: h * 0.50))
                path.addLine(to: CGPoint(x: w * 0.65, y: h * 0.78))
            case .plus:
                path.move(to: CGPoint(x: w * 0.50, y: h * 0.22))
                path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.78))
                path.move(to: CGPoint(x: w * 0.22, y: h * 0.50))
                path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.50))
            case .check:
                path.move(to: CGPoint(x: w * 0.22, y: h * 0.54))
                path.addLine(to: CGPoint(x: w * 0.43, y: h * 0.72))
                path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.30))
            case .xmark:
                path.move(to: CGPoint(x: w * 0.28, y: h * 0.28))
                path.addLine(to: CGPoint(x: w * 0.72, y: h * 0.72))
                path.move(to: CGPoint(x: w * 0.72, y: h * 0.28))
                path.addLine(to: CGPoint(x: w * 0.28, y: h * 0.72))
            case .circle:
                path.addEllipse(in: CGRect(x: w * 0.24, y: h * 0.24, width: w * 0.52, height: h * 0.52))
            case .arrowUp:
                path.move(to: CGPoint(x: w * 0.50, y: h * 0.78))
                path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.24))
                path.move(to: CGPoint(x: w * 0.28, y: h * 0.46))
                path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.24))
                path.addLine(to: CGPoint(x: w * 0.72, y: h * 0.46))
            case .arrowDown:
                path.move(to: CGPoint(x: w * 0.50, y: h * 0.22))
                path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.76))
                path.move(to: CGPoint(x: w * 0.28, y: h * 0.54))
                path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.76))
                path.addLine(to: CGPoint(x: w * 0.72, y: h * 0.54))
            case .arrows:
                path.move(to: CGPoint(x: w * 0.24, y: h * 0.34))
                path.addLine(to: CGPoint(x: w * 0.72, y: h * 0.34))
                path.move(to: CGPoint(x: w * 0.56, y: h * 0.20))
                path.addLine(to: CGPoint(x: w * 0.72, y: h * 0.34))
                path.addLine(to: CGPoint(x: w * 0.56, y: h * 0.48))
                path.move(to: CGPoint(x: w * 0.76, y: h * 0.66))
                path.addLine(to: CGPoint(x: w * 0.28, y: h * 0.66))
                path.move(to: CGPoint(x: w * 0.44, y: h * 0.52))
                path.addLine(to: CGPoint(x: w * 0.28, y: h * 0.66))
                path.addLine(to: CGPoint(x: w * 0.44, y: h * 0.80))
            case .list:
                for y in [0.30, 0.50, 0.70] {
                    path.move(to: CGPoint(x: w * 0.32, y: h * y))
                    path.addLine(to: CGPoint(x: w * 0.78, y: h * y))
                    path.move(to: CGPoint(x: w * 0.20, y: h * y))
                    path.addLine(to: CGPoint(x: w * 0.21, y: h * y))
                }
            case .play:
                path.move(to: CGPoint(x: w * 0.38, y: h * 0.28))
                path.addLine(to: CGPoint(x: w * 0.74, y: h * 0.50))
                path.addLine(to: CGPoint(x: w * 0.38, y: h * 0.72))
                path.closeSubpath()
                context.fill(path, with: .color(color))
                return
            case .refresh:
                path.addArc(
                    center: CGPoint(x: w * 0.50, y: h * 0.52),
                    radius: min(w, h) * 0.30,
                    startAngle: .degrees(35),
                    endAngle: .degrees(315),
                    clockwise: true
                )
                path.move(to: CGPoint(x: w * 0.70, y: h * 0.21))
                path.addLine(to: CGPoint(x: w * 0.76, y: h * 0.42))
                path.addLine(to: CGPoint(x: w * 0.56, y: h * 0.36))
            default:
                break
            }

            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: max(1.6, size * 0.12), lineCap: .round, lineJoin: .round)
            )
        }
    }

    private var copyGlyph: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let line = max(1.5, size * 0.1)
            let back = Path(roundedRect: CGRect(
                x: w * 0.20,
                y: h * 0.16,
                width: w * 0.44,
                height: h * 0.52
            ), cornerRadius: size * 0.10)
            let front = Path(roundedRect: CGRect(
                x: w * 0.36,
                y: h * 0.32,
                width: w * 0.44,
                height: h * 0.52
            ), cornerRadius: size * 0.10)
            context.stroke(back, with: .color(color.opacity(0.58)), lineWidth: line)
            context.stroke(front, with: .color(color), lineWidth: line)
        }
    }

    private var externalGlyph: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let line = max(1.5, size * 0.11)
            var path = Path()
            path.addRoundedRect(
                in: CGRect(x: w * 0.18, y: h * 0.30, width: w * 0.52, height: h * 0.52),
                cornerSize: CGSize(width: size * 0.10, height: size * 0.10)
            )
            context.stroke(path, with: .color(color.opacity(0.72)), lineWidth: line)

            var arrow = Path()
            arrow.move(to: CGPoint(x: w * 0.42, y: h * 0.58))
            arrow.addLine(to: CGPoint(x: w * 0.78, y: h * 0.22))
            arrow.move(to: CGPoint(x: w * 0.56, y: h * 0.22))
            arrow.addLine(to: CGPoint(x: w * 0.78, y: h * 0.22))
            arrow.addLine(to: CGPoint(x: w * 0.78, y: h * 0.44))
            context.stroke(
                arrow,
                with: .color(color),
                style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private var settingsGlyph: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let line = max(1.5, size * 0.10)
            for (y, knob) in [(0.30, 0.38), (0.50, 0.65), (0.70, 0.46)] {
                var path = Path()
                path.move(to: CGPoint(x: w * 0.18, y: h * y))
                path.addLine(to: CGPoint(x: w * 0.82, y: h * y))
                context.stroke(path, with: .color(color.opacity(0.72)), lineWidth: line)
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: w * knob - size * 0.10,
                        y: h * y - size * 0.10,
                        width: size * 0.20,
                        height: size * 0.20
                    )),
                    with: .color(color)
                )
            }
        }
    }

    private var networkSettingsGlyph: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let line = max(1.5, size * 0.10)
            let center = CGPoint(x: w * 0.50, y: h * 0.50)
            let rayStart = size * 0.29
            let rayEnd = size * 0.39

            context.stroke(
                Path(ellipseIn: CGRect(
                    x: center.x - size * 0.13,
                    y: center.y - size * 0.13,
                    width: size * 0.26,
                    height: size * 0.26
                )),
                with: .color(color),
                lineWidth: line
            )

            for index in 0 ..< 8 {
                let angle = Double(index) * Double.pi / 4
                let x = CGFloat(cos(angle))
                let y = CGFloat(sin(angle))
                let start = CGPoint(
                    x: center.x + x * rayStart,
                    y: center.y + y * rayStart
                )
                let end = CGPoint(
                    x: center.x + x * rayEnd,
                    y: center.y + y * rayEnd
                )
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                context.stroke(
                    path,
                    with: .color(color.opacity(0.78)),
                    style: StrokeStyle(lineWidth: line, lineCap: .round)
                )
            }
        }
    }

    private var searchGlyph: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let line = max(1.6, size * 0.12)
            var path = Path()
            path.addEllipse(in: CGRect(x: w * 0.20, y: h * 0.18, width: w * 0.44, height: h * 0.44))
            path.move(to: CGPoint(x: w * 0.58, y: h * 0.58))
            path.addLine(to: CGPoint(x: w * 0.80, y: h * 0.80))
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private var waveGlyph: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let line = max(1.5, size * 0.10)
            for offset in [0.22, 0.40, 0.58] {
                var path = Path()
                path.move(to: CGPoint(x: w * offset, y: h * 0.28))
                path.addCurve(
                    to: CGPoint(x: w * offset, y: h * 0.72),
                    control1: CGPoint(x: w * (offset + 0.16), y: h * 0.36),
                    control2: CGPoint(x: w * (offset + 0.16), y: h * 0.64)
                )
                context.stroke(
                    path,
                    with: .color(color.opacity(offset == 0.58 ? 1 : 0.58)),
                    style: StrokeStyle(lineWidth: line, lineCap: .round)
                )
            }
        }
    }

    private var lockGlyph: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let line = max(1.5, size * 0.10)
            var shackle = Path()
            shackle.addArc(
                center: CGPoint(x: w * 0.50, y: h * 0.42),
                radius: w * 0.20,
                startAngle: .degrees(200),
                endAngle: .degrees(-20),
                clockwise: false
            )
            context.stroke(shackle, with: .color(color), style: StrokeStyle(lineWidth: line, lineCap: .round))
            let rect = Path(
                roundedRect: CGRect(x: w * 0.24, y: h * 0.44, width: w * 0.52, height: h * 0.36),
                cornerRadius: size * 0.10
            )
            context.stroke(rect, with: .color(color), lineWidth: line)
        }
    }

    private var faceIDGlyph: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let line = max(1.4, size * 0.09)
            var path = Path()
            path.move(to: CGPoint(x: w * 0.28, y: h * 0.22))
            path.addLine(to: CGPoint(x: w * 0.22, y: h * 0.22))
            path.addLine(to: CGPoint(x: w * 0.22, y: h * 0.32))
            path.move(to: CGPoint(x: w * 0.72, y: h * 0.22))
            path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.22))
            path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.32))
            path.move(to: CGPoint(x: w * 0.22, y: h * 0.68))
            path.addLine(to: CGPoint(x: w * 0.22, y: h * 0.78))
            path.addLine(to: CGPoint(x: w * 0.32, y: h * 0.78))
            path.move(to: CGPoint(x: w * 0.78, y: h * 0.68))
            path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.78))
            path.addLine(to: CGPoint(x: w * 0.68, y: h * 0.78))
            path.move(to: CGPoint(x: w * 0.38, y: h * 0.42))
            path.addLine(to: CGPoint(x: w * 0.38, y: h * 0.43))
            path.move(to: CGPoint(x: w * 0.62, y: h * 0.42))
            path.addLine(to: CGPoint(x: w * 0.62, y: h * 0.43))
            path.move(to: CGPoint(x: w * 0.42, y: h * 0.64))
            path.addCurve(
                to: CGPoint(x: w * 0.62, y: h * 0.64),
                control1: CGPoint(x: w * 0.48, y: h * 0.70),
                control2: CGPoint(x: w * 0.56, y: h * 0.70)
            )
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private var shieldGlyph: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let line = max(1.5, size * 0.10)
            var path = Path()
            path.move(to: CGPoint(x: w * 0.50, y: h * 0.14))
            path.addLine(to: CGPoint(x: w * 0.76, y: h * 0.25))
            path.addLine(to: CGPoint(x: w * 0.70, y: h * 0.62))
            path.addCurve(
                to: CGPoint(x: w * 0.50, y: h * 0.84),
                control1: CGPoint(x: w * 0.66, y: h * 0.74),
                control2: CGPoint(x: w * 0.58, y: h * 0.80)
            )
            path.addCurve(
                to: CGPoint(x: w * 0.30, y: h * 0.62),
                control1: CGPoint(x: w * 0.42, y: h * 0.80),
                control2: CGPoint(x: w * 0.34, y: h * 0.74)
            )
            path.addLine(to: CGPoint(x: w * 0.24, y: h * 0.25))
            path.closeSubpath()
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: line, lineJoin: .round))
        }
    }

    private var tokenGridGlyph: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let radius = size * 0.10
            for x in [0.28, 0.50, 0.72] {
                for y in [0.30, 0.52, 0.74] where !(x == 0.50 && y == 0.52) {
                    context.stroke(
                        Path(ellipseIn: CGRect(
                            x: w * x - radius,
                            y: h * y - radius,
                            width: radius * 2,
                            height: radius * 2
                        )),
                        with: .color(color),
                        lineWidth: max(1.2, size * 0.08)
                    )
                }
            }
        }
    }

    private var imageGlyph: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let line = max(1.5, size * 0.10)
            let rect = Path(
                roundedRect: CGRect(x: w * 0.18, y: h * 0.24, width: w * 0.64, height: h * 0.52),
                cornerRadius: size * 0.10
            )
            context.stroke(rect, with: .color(color), lineWidth: line)
            var path = Path()
            path.move(to: CGPoint(x: w * 0.25, y: h * 0.68))
            path.addLine(to: CGPoint(x: w * 0.42, y: h * 0.52))
            path.addLine(to: CGPoint(x: w * 0.54, y: h * 0.64))
            path.addLine(to: CGPoint(x: w * 0.64, y: h * 0.54))
            path.addLine(to: CGPoint(x: w * 0.76, y: h * 0.68))
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
            )
            context.fill(
                Path(ellipseIn: CGRect(x: w * 0.60, y: h * 0.34, width: w * 0.10, height: h * 0.10)),
                with: .color(color)
            )
        }
    }

    private var keyGlyph: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let line = max(1.5, size * 0.10)
            var path = Path()
            path.addEllipse(in: CGRect(x: w * 0.16, y: h * 0.34, width: w * 0.28, height: h * 0.28))
            path.move(to: CGPoint(x: w * 0.44, y: h * 0.48))
            path.addLine(to: CGPoint(x: w * 0.82, y: h * 0.48))
            path.move(to: CGPoint(x: w * 0.64, y: h * 0.48))
            path.addLine(to: CGPoint(x: w * 0.64, y: h * 0.62))
            path.move(to: CGPoint(x: w * 0.76, y: h * 0.48))
            path.addLine(to: CGPoint(x: w * 0.76, y: h * 0.58))
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private var documentGlyph: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let line = max(1.5, size * 0.10)
            var path = Path()
            path.move(to: CGPoint(x: w * 0.28, y: h * 0.14))
            path.addLine(to: CGPoint(x: w * 0.60, y: h * 0.14))
            path.addLine(to: CGPoint(x: w * 0.76, y: h * 0.30))
            path.addLine(to: CGPoint(x: w * 0.76, y: h * 0.86))
            path.addLine(to: CGPoint(x: w * 0.28, y: h * 0.86))
            path.closeSubpath()
            path.move(to: CGPoint(x: w * 0.60, y: h * 0.14))
            path.addLine(to: CGPoint(x: w * 0.60, y: h * 0.32))
            path.addLine(to: CGPoint(x: w * 0.76, y: h * 0.32))
            path.move(to: CGPoint(x: w * 0.38, y: h * 0.50))
            path.addLine(to: CGPoint(x: w * 0.66, y: h * 0.50))
            path.move(to: CGPoint(x: w * 0.38, y: h * 0.64))
            path.addLine(to: CGPoint(x: w * 0.66, y: h * 0.64))
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private var warningGlyph: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let line = max(1.5, size * 0.10)
            var path = Path()
            path.move(to: CGPoint(x: w * 0.50, y: h * 0.14))
            path.addLine(to: CGPoint(x: w * 0.86, y: h * 0.78))
            path.addLine(to: CGPoint(x: w * 0.14, y: h * 0.78))
            path.closeSubpath()
            path.move(to: CGPoint(x: w * 0.50, y: h * 0.34))
            path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.56))
            path.move(to: CGPoint(x: w * 0.50, y: h * 0.68))
            path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.69))
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private var clockGlyph: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let line = max(1.5, size * 0.10)
            var path = Path()
            path.addEllipse(in: CGRect(x: w * 0.18, y: h * 0.18, width: w * 0.64, height: h * 0.64))
            path.move(to: CGPoint(x: w * 0.50, y: h * 0.32))
            path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.52))
            path.addLine(to: CGPoint(x: w * 0.65, y: h * 0.62))
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

// swiftlint:enable type_body_length identifier_name

struct CosignGlyphButton: View {
    let glyph: CosignGlyph
    var accessibilityLabel: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CosignGlyphView(glyph: glyph, size: 16, color: CosignTheme.inkDim)
                .frame(width: 34, height: 34)
                .background(CosignTheme.surface, in: .circle)
                .overlay {
                    Circle().stroke(CosignTheme.line, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? "")
    }
}

// swiftlint:enable file_length
