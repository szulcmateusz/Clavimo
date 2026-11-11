import ClavimoCore
import SwiftUI

/// A trackpad drawn as a rounded rectangle with the fingers of a gesture:
/// dots for fingers, a ring for the tapping finger of a tip tap, an arrow
/// for swipes and a highlighted corner for corner clicks.
struct TrackpadGlyph: View {
    let model: TrackpadGlyphModel
    var size = CGSize(width: 30, height: 21)

    var body: some View {
        Canvas { context, canvas in
            let rect = CGRect(origin: .zero, size: canvas).insetBy(dx: 0.75, dy: 0.75)
            let radius = rect.height * 0.22
            let surface = Path(roundedRect: rect, cornerRadius: radius)
            context.fill(surface, with: .color(Brand.mint.opacity(0.18)))
            context.stroke(surface, with: .color(Brand.mint), lineWidth: 1.2)

            let dot = max(3.5, rect.height * 0.2)
            if let corner = model.corner {
                let quarter = CGSize(width: rect.width * 0.36, height: rect.height * 0.42)
                let origin = CGPoint(
                    x: corner == .topLeft || corner == .bottomLeft ? rect.minX : rect.maxX - quarter.width,
                    y: corner == .topLeft || corner == .topRight ? rect.minY : rect.maxY - quarter.height
                )
                let region = Path(roundedRect: CGRect(origin: origin, size: quarter), cornerRadius: radius * 0.8)
                context.fill(region, with: .color(Brand.mint.opacity(0.45)))
                let center = CGPoint(x: origin.x + quarter.width / 2, y: origin.y + quarter.height / 2)
                drawFinger(&context, at: center, size: dot)
                return
            }

            let count = max(model.fingers, 1)
            let spacing = min(dot * 1.6, rect.width * 0.8 / CGFloat(count))
            let totalWidth = spacing * CGFloat(count - 1)
            var centerY = rect.midY
            if let arrow = model.arrow, arrow == .up || arrow == .down { centerY = rect.midY + (arrow == .up ? 2 : -2) }
            for index in 0..<count {
                let center = CGPoint(x: rect.midX - totalWidth / 2 + spacing * CGFloat(index), y: centerY)
                if let side = model.tipTapSide, index == (side == .left ? 0 : count - 1) {
                    context.stroke(Path(ellipseIn: CGRect(x: center.x - dot / 2, y: center.y - dot / 2, width: dot, height: dot)),
                                   with: .color(Brand.mint), lineWidth: 1.4)
                } else {
                    drawFinger(&context, at: center, size: dot)
                }
            }
            if let arrow = model.arrow {
                drawArrow(&context, arrow, in: rect, fingersWidth: totalWidth + dot)
            }
            if let rotation = model.rotation {
                // A circular arrow around the two fingers.
                let ring = rect.height * 0.36
                let center = CGPoint(x: rect.midX, y: rect.midY)
                let clockwise = rotation == .clockwise
                var arc = Path()
                arc.addArc(center: center, radius: ring, startAngle: .degrees(clockwise ? 200 : -20),
                           endAngle: .degrees(clockwise ? 340 : 160), clockwise: !clockwise)
                context.stroke(arc, with: .color(Brand.mint), lineWidth: 1.2)
                let tipAngle = (clockwise ? 340.0 : 160.0) * .pi / 180
                let tip = CGPoint(x: center.x + ring * cos(tipAngle), y: center.y + ring * sin(tipAngle))
                context.fill(Path(ellipseIn: CGRect(x: tip.x - 1.6, y: tip.y - 1.6, width: 3.2, height: 3.2)), with: .color(Brand.mint))
            }
            if let zone = model.zone {
                let half: CGRect = switch zone {
                case .left: CGRect(x: rect.minX, y: rect.minY, width: rect.width / 2, height: rect.height)
                case .right: CGRect(x: rect.midX, y: rect.minY, width: rect.width / 2, height: rect.height)
                case .top: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height / 2)
                case .bottom: CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2)
                }
                context.fill(Path(roundedRect: half, cornerRadius: radius * 0.6), with: .color(Brand.mint.opacity(0.22)))
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }

    private func drawFinger(_ context: inout GraphicsContext, at center: CGPoint, size: CGFloat) {
        let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        context.fill(Path(ellipseIn: rect), with: .color(Brand.mint))
        if model.pressed {
            context.stroke(Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)), with: .color(Brand.mint.opacity(0.6)), lineWidth: 1)
        }
    }

    private func drawArrow(_ context: inout GraphicsContext, _ direction: GestureEvent.Direction, in rect: CGRect, fingersWidth: CGFloat) {
        var path = Path()
        let head: CGFloat = 3
        let horizontal = direction == .left || direction == .right
        let length = horizontal ? min(rect.width * 0.7, fingersWidth + 6) : rect.height * 0.32
        let center = horizontal ? CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.2)
            : CGPoint(x: rect.midX, y: direction == .up ? rect.minY + rect.height * 0.25 : rect.maxY - rect.height * 0.25)
        let (start, end): (CGPoint, CGPoint) = switch direction {
        case .left: (CGPoint(x: center.x + length / 2, y: center.y), CGPoint(x: center.x - length / 2, y: center.y))
        case .right: (CGPoint(x: center.x - length / 2, y: center.y), CGPoint(x: center.x + length / 2, y: center.y))
        case .up: (CGPoint(x: center.x, y: center.y + length / 2), CGPoint(x: center.x, y: center.y - length / 2))
        case .down: (CGPoint(x: center.x, y: center.y - length / 2), CGPoint(x: center.x, y: center.y + length / 2))
        }
        path.move(to: start)
        path.addLine(to: end)
        let back: CGPoint = switch direction {
        case .left: CGPoint(x: head, y: 0)
        case .right: CGPoint(x: -head, y: 0)
        case .up: CGPoint(x: 0, y: head)
        case .down: CGPoint(x: 0, y: -head)
        }
        let side = CGPoint(x: back.y, y: back.x)
        path.move(to: CGPoint(x: end.x + back.x + side.x, y: end.y + back.y + side.y))
        path.addLine(to: end)
        path.addLine(to: CGPoint(x: end.x + back.x - side.x, y: end.y + back.y - side.y))
        context.stroke(path, with: .color(Brand.violet), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
    }
}

/// A gesture shown as a trackpad drawing with its name, like the mouse
/// button token.
struct TrackpadToken: View {
    let model: TrackpadGlyphModel
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            TrackpadGlyph(model: model, size: CGSize(width: 24, height: 17))
            Text(title)
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 7)
        .frame(minHeight: 24)
        .background(Brand.mint.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
