import SwiftUI

/// The colours a job can be given. Stored as the case name rather than a hex
/// string so the palette can be retuned later without rewriting the store.
enum JobColor: String, CaseIterable, Identifiable, Codable {
    case blue, orange, green, purple, pink, red, teal, indigo, brown, yellow

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: return .blue
        case .orange: return .orange
        // The app icon's green. Not SwiftUI's `.green`, which is a shade
        // yellower and read as a near-miss next to the icon.
        case .green: return Color(red: 0.176, green: 0.804, blue: 0.439)
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .teal: return .teal
        case .indigo: return .indigo
        case .brown: return .brown
        case .yellow: return .yellow
        }
    }

    /// The darker end of the hero card's gradient.
    var gradientEnd: Color {
        switch self {
        case .blue: return Color(red: 0.11, green: 0.33, blue: 0.78)
        case .orange: return Color(red: 0.93, green: 0.33, blue: 0.22)
        case .green: return Color(red: 0.078, green: 0.627, blue: 0.345)
        case .purple: return Color(red: 0.45, green: 0.18, blue: 0.70)
        case .pink: return Color(red: 0.80, green: 0.18, blue: 0.45)
        case .red: return Color(red: 0.70, green: 0.12, blue: 0.16)
        case .teal: return Color(red: 0.06, green: 0.45, blue: 0.50)
        case .indigo: return Color(red: 0.20, green: 0.20, blue: 0.65)
        case .brown: return Color(red: 0.40, green: 0.26, blue: 0.14)
        case .yellow: return Color(red: 0.85, green: 0.55, blue: 0.05)
        }
    }

    var label: String { rawValue.capitalized }
}

/// SF Symbols offered in the job editor. A fixed list rather than a free text
/// field — a typo'd symbol name renders as nothing at all.
enum JobSymbol {
    static let all = [
        "briefcase.fill", "fork.knife", "cup.and.saucer.fill", "wineglass.fill",
        "chevron.left.forwardslash.chevron.right", "desktopcomputer", "pencil.and.ruler.fill",
        "stethoscope", "cross.case.fill", "graduationcap.fill", "book.fill",
        "hammer.fill", "wrench.and.screwdriver.fill", "paintbrush.fill",
        "car.fill", "bicycle", "shippingbox.fill", "cart.fill",
        "scissors", "camera.fill", "music.mic", "leaf.fill",
        "pawprint.fill", "figure.and.child.holdinghands", "sparkles", "star.fill"
    ]

    static let fallback = "briefcase.fill"
}
