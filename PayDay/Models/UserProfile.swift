import SwiftUI

/// The handful of things the app knows about you. No account, no server —
/// just defaults, filled in whenever you feel like it and skippable entirely.
enum UserProfile {
    static let nameKey = "profileName"
    static let roleKey = "profileRole"
    /// Shown in the avatar instead of initials. Empty means initials.
    static let emojiKey = "profileEmoji"
    /// Your colour. It tints the Profile tab the way a job's colour tints
    /// its own — each tab carries the colour of what it's about. It stops at
    /// the tab, which is what went wrong the first time: it used to leak into
    /// chrome that had nothing to do with you.
    static let colorKey = "profileColor"
    static let defaultColor = JobColor.green
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
