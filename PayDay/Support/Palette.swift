import SwiftUI

/// The app's own colours, as opposed to any one job's.
///
/// Two roles, deliberately kept apart:
///
/// - **Brand green is money.** Every amount, on every screen, always. This is
///   the thread that ties the inside of the app to its icon and its first
///   screen.
/// - **A job's colour is hours and identity** — its tab, its card, its figures
///   for time worked.
///
/// Mixing the two is what made the app feel like two apps: the welcome screen
/// was green, and inside, money was sometimes system green, sometimes whatever
/// colour the job happened to be. One rule fixes it without painting
/// everything green, which would throw away the per-job colours entirely.
enum Palette {
    /// The green the app icon is drawn in. Same value as `JobColor.green`, so
    /// a job coloured green and the brand agree rather than nearly agreeing.
    static let brand = Color(red: 0.176, green: 0.804, blue: 0.439)
    static let brandDeep = Color(red: 0.078, green: 0.627, blue: 0.345)

    /// Money earned, paid, projected. Always this.
    static var money: Color { brand }

    /// Something worth a second look: a short payslip, sync that isn't running.
    static let attention = Color.orange

    /// The gradient the icon and the welcome mark use.
    static var brandGradient: LinearGradient {
        LinearGradient(colors: [Color(red: 0.29, green: 0.87, blue: 0.50), brandDeep],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Shape

    /// One radius for cards, one for the tiles inside them. The app used
    /// seven different values before, which reads as unfinished long before
    /// anyone can say why.
    static let cardRadius: CGFloat = 18
    static let tileRadius: CGFloat = 12
}

extension View {
    /// The app's standard card.
    func card(padding: CGFloat = 14) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous)
            )
    }
}

/// The wordmark, at whatever size. Used on the welcome screen and small at
/// the foot of Profile — the two places the app says its own name.
struct PayDayMark: View {
    var size: CGFloat = 104

    var body: some View {
        VStack(spacing: 0) {
            Text("Pay").foregroundStyle(.white)
            Text("Day").foregroundStyle(Color(white: 0.09))
        }
        .font(.system(size: size * 0.29, weight: .heavy, design: .rounded))
        .frame(width: size, height: size)
        .background(Palette.brandGradient,
                    in: RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
    }
}

extension Bundle {
    /// "1.0" — the marketing version, for the footer in Profile.
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
