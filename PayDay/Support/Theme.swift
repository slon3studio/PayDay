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

/// The chosen theme, applied to the window rather than to a view.
///
/// `preferredColorScheme` left sheets behind. Going from Light back to
/// System changed the app but not the open sheet, because a view that has
/// once been handed a concrete scheme doesn't go back when it's later handed
/// `nil` — and a sheet, presented in its own context, kept the one it was
/// born with. The override belongs to the window every sheet is presented
/// in, where `.unspecified` really does mean "whatever the phone says".
enum AppAppearance {
    static func apply(_ appearance: Appearance) {
        let style: UIUserInterfaceStyle = {
            switch appearance {
            case .system: return .unspecified
            case .light: return .light
            case .dark: return .dark
            }
        }()
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)

        // At launch the first `onAppear` can land before the window exists,
        // which would leave the setting unapplied until it next changed.
        guard !windows.isEmpty else {
            DispatchQueue.main.async { apply(appearance) }
            return
        }

        for window in windows {
            window.overrideUserInterfaceStyle = style
        }
    }
}

extension View {
    /// Keeps the window's appearance in step with the setting. Applied once,
    /// at the root — everything presented from there inherits it.
    func appAppearance() -> some View {
        modifier(AppearanceWatcher())
    }
}

private struct AppearanceWatcher: ViewModifier {
    @AppStorage(Appearance.key) private var raw: String = Appearance.system.rawValue

    func body(content: Content) -> some View {
        content
            .onAppear { AppAppearance.apply(Appearance(rawValue: raw) ?? .system) }
            .onChange(of: raw) { _, new in
                AppAppearance.apply(Appearance(rawValue: new) ?? .system)
            }
    }
}

/// One bar split into parts, for showing a total's composition without
/// three separate numbers having to be compared by eye.
struct ProportionBar: View {
    enum Style {
        case solid, half, faint
        var opacity: Double {
            switch self {
            case .solid: return 1
            case .half: return 0.45
            case .faint: return 0.18
            }
        }
    }

    struct Part {
        let value: Double
        let colour: Color
        let style: Style
    }

    let parts: [Part]
    var height: CGFloat = 10

    private var total: Double { max(parts.reduce(0) { $0 + $1.value }, 0.0001) }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    if part.value > 0 {
                        Capsule()
                            .fill(part.colour.opacity(part.style.opacity))
                            .frame(width: max(3, geometry.size.width * part.value / total))
                    }
                }
            }
        }
        .frame(height: height)
    }
}

/// A compact segmented control in the app's own language — a pill that slides
/// along a faint track. The stock segmented picker is the most recognisably
/// system-issued control there is, and two of them stacked made the chart
/// look like a settings pane with a graph attached.
struct ChipPicker<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let label: String
        var id: Value { value }

        init(_ value: Value, _ label: String) {
            self.value = value
            self.label = label
        }
    }

    let options: [Option]
    @Binding var selection: Value
    var tint: Color = Palette.brand

    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isOn = option.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.22)) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(isOn ? .white : Color.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            if isOn {
                                Capsule()
                                    .fill(tint)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color(.tertiarySystemFill), in: Capsule())
    }
}
