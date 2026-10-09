import SwiftUI

/// A single number in the stats grid.
struct StatTile: View {
    let title: String
    let value: String
    var caption: String? = nil
    var tint: Color = .secondary
    /// Inside another card the tile needs a fill of its own to stand out.
    var background: Color = Color(.secondarySystemGroupedBackground)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint == .secondary ? Color.primary : tint)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(background, in: RoundedRectangle(cornerRadius: Palette.tileRadius, style: .continuous))
    }
}

/// Two-column grid of stat tiles.
struct StatGrid<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            content
        }
    }
}

/// A labelled row inside a card.
struct StatRow: View {
    let label: String
    let value: String
    var emphasized: Bool = false
    var tint: Color? = nil

    var body: some View {
        HStack {
            Text(label)
                .font(emphasized ? .body.weight(.semibold) : .body)
                .foregroundStyle(emphasized ? Color.primary : .secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(emphasized ? .body.weight(.bold) : .body.weight(.medium))
                .foregroundStyle(tint ?? .primary)
                .monospacedDigit()
        }
    }
}
