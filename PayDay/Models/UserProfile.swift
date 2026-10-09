import SwiftUI

/// The handful of things the app knows about you. No account, no server —
/// just defaults, filled in whenever you feel like it and skippable entirely.
enum UserProfile {
    static let nameKey = "profileName"
    static let roleKey = "profileRole"
    /// Shown in the avatar instead of initials. Empty means initials.
    static let emojiKey = "profileEmoji"
    // There was a profile colour here, and it was the one piece of
    // customisation that bought nothing. It recoloured the Profile tab and
    // Settings and left the rest of the app green, so which tab you were on
    // decided what the app looked like. PayDay's chrome is PayDay's colour
    // now, always. Job colours remain, because telling two jobs apart at a
    // glance is work worth doing.
    static let startedKey = "profileStarted"

    static var name: String {
        UserDefaults.standard.string(forKey: nameKey) ?? ""
    }

    static var role: String {
        UserDefaults.standard.string(forKey: roleKey) ?? ""
    }

    /// The day the app was first opened, so the profile can say how long
    /// you've been tracking without inventing a sign-up date.
    static var started: Date {
        let defaults = UserDefaults.standard
        if let saved = defaults.object(forKey: startedKey) as? Date { return saved }
        let now = Date()
        defaults.set(now, forKey: startedKey)
        return now
    }
}

/// Light or dark, or whatever the phone is set to.
enum Appearance: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    static let key = "appearance"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
