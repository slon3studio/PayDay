import SwiftUI

// The pieces that make a screen look like this app rather than like a
// well-made iOS app in general.
//
// The icon and the welcome screen set the vocabulary: heavy rounded type,
// wide tracking on small labels, green for money, a tile with a symbol in it.
// Everything here is that vocabulary written down so the rest of the app can
// speak it without each view inventing its own version.

/// Every section header in the app. Small, heavy, widely tracked — the same
/// treatment as the eyebrow on the cards, which is what ties a plain list to
/// the designed parts of a screen.
struct SectionHeader: View {
    private let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(1.1)
            .foregroundStyle(.secondary)
            // The list would otherwise uppercase an already-uppercased string
            // and lose the tracking.
            .textCase(nil)
    }
}

/// The small label above a figure inside a card. Same idea as the section
/// header, sized for a coloured surface.
struct Eyebrow: View {
    private let title: String
    private let opacity: Double

    init(_ title: String, opacity: Double = 0.85) {
        self.title = title
        self.opacity = opacity
    }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .tracking(0.8)
            .opacity(opacity)
    }
}

/// A symbol in a tinted tile — the shape the welcome screen's bullets, the
/// job rows and the template grid all use.
struct SymbolTile: View {
    let symbol: String
    var colour: Color = Palette.brand
    var size: CGFloat = 40
    /// Filled with the colour, or the colour on a faint wash of it.
    var solid = true

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(solid ? AnyShapeStyle(.white) : AnyShapeStyle(colour))
            .frame(width: size, height: size)
            .background {
                if solid {
                    RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                        .fill(LinearGradient(colors: [colour, colour.opacity(0.75)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                    RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                        .fill(colour.opacity(0.14))
                }
            }
    }
}

/// An amount, always drawn the same way: rounded, heavy, monospaced digits,
/// and green unless it's sitting on a coloured card.
struct MoneyText: View {
    let amount: Double
    var size: CGFloat = 34
    var colour: Color = Palette.money

    var body: some View {
        Text(Fmt.money(amount))
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(colour)
            .contentTransition(.numericText())
            .minimumScaleFactor(0.6)
            .lineLimit(1)
    }
}

/// What a screen shows when there is nothing on it yet. The stock
/// `ContentUnavailableView` is recognisably Apple's; this one is the app's,
/// and it carries the same tile and type as everything else.
struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var tint: Color = Palette.brand
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            SymbolTile(symbol: symbol, colour: tint, size: 64)

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .tint(tint)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 36)
    }
}

extension View {
    /// A card's padding and background, for the ones built by hand rather
    /// than out of a Form section.
    func cardSurface(padding: CGFloat = 16) -> some View {
        self.padding(.horizontal, padding)
            .padding(.vertical, 14)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous)
            )
    }
}
