import SwiftUI

/// Colors, spacing and small building blocks shared by every screen, so
/// the app looks consistent and adapts to light and dark mode.
enum Brand {
    /// The violet of the keycap in the logo.
    static let violet = Color(red: 0x8C / 255, green: 0x76 / 255, blue: 0xF2 / 255)
    /// The mint of the mouse in the logo.
    static let mint = Color(red: 0x3F / 255, green: 0xD8 / 255, blue: 0xC4 / 255)
    /// The logo's tile colors, for hero surfaces.
    static let nightTop = Color(red: 0x2B / 255, green: 0x27 / 255, blue: 0x52 / 255)
    static let nightBottom = Color(red: 0x0D / 255, green: 0x0B / 255, blue: 0x1F / 255)

    static var heroGradient: LinearGradient {
        LinearGradient(colors: [nightTop, nightBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// A rounded surface that groups related content.
struct Card<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.5)))
    }
}

/// A colored capsule with text: state is never shown by color alone.
struct StatusChip: View {
    enum Kind {
        case active, paused, off, problem, beta, info

        var color: Color {
            switch self {
            case .active: .green
            case .paused: .orange
            case .off: .secondary
            case .problem: .red
            case .beta: Brand.violet
            case .info: .blue
            }
        }
    }

    let text: String
    let kind: Kind

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, 3)
            .background(kind.color.opacity(0.14), in: Capsule())
            .foregroundStyle(kind.color)
    }
}

/// A key drawn like a physical keycap, with an optional side caption
/// such as "L" or "R" for left and right modifiers.
struct KeyCap: View {
    let label: String
    var caption: String?

    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(.callout, design: .rounded).weight(.semibold))
            if let caption {
                Text(caption)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 7)
        .frame(minWidth: 28, minHeight: 24)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.18), radius: 0, x: 0, y: 1.5)
        )
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption.map { "\(label) \($0)" } ?? label)
    }
}

/// A mouse button shown as a small mint mouse with the button's name.
struct MouseButtonToken: View {
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "computermouse.fill")
                .foregroundStyle(Brand.mint)
            Text(title)
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 7)
        .frame(minHeight: 24)
        .background(Brand.mint.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// An action shown as a violet chip.
struct ActionToken: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.callout.weight(.medium))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8)
            .frame(minHeight: 24)
            .background(Brand.violet.opacity(0.16), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .foregroundStyle(Brand.violet)
    }
}

/// A row of tokens describing a rule's trigger and result.
struct RuleTokensView: View {
    let tokens: [RuleToken]

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                switch token {
                case let .key(label, caption): KeyCap(label: label, caption: caption)
                case let .mouse(title): MouseButtonToken(title: title)
                case let .action(title, symbol): ActionToken(title: title, symbol: symbol)
                case let .symbol(name):
                    Image(systemName: name)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                case let .text(text):
                    Text(text).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A heading for a group of settings with an optional explanation.
struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3.weight(.semibold))
            if let subtitle {
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

extension View {
    /// Explanatory text under a grouped form section, aligned with the
    /// section content even when it wraps to several lines.
    func formFooterStyle() -> some View {
        self.font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
