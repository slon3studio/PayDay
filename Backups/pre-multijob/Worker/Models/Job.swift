import SwiftUI

/// The two jobs tracked by the app.
enum Job: String, CaseIterable, Codable, Identifiable {
    case ijs
    case macek

    var id: String { rawValue }

    /// The cat hides in Maček's name; IJS gets its programmer alongside.
    var displayName: String {
        switch self {
        case .ijs: return "IJS 👨‍💻"
        case .macek: return "M🐱ček"
        }
    }

    var subtitle: String {
        switch self {
        case .ijs: return "Programming"
        case .macek: return "Waiting tables"
        }
    }

    /// The rate before it became a setting. Shifts logged back then don't
    /// carry a rate of their own, so they're paid at this.
    var defaultHourlyRate: Double {
        switch self {
        case .ijs: return 9.25
        case .macek: return 9.00
        }
    }

    var hourlyRateKey: String { "hourlyRate.\(rawValue)" }

    /// The current rate, from Settings. New shifts are stamped with it.
    var hourlyRate: Double {
        let saved = UserDefaults.standard.double(forKey: hourlyRateKey)
        return saved > 0 ? saved : defaultHourlyRate
    }

    /// Only the waiter job records tips.
    var tracksTips: Bool { self == .macek }

    /// Whether weekend shifts are on the table. The institute is Mon–Fri; a bar
    /// very much isn't, so projecting Maček across weekdays only undercounts it.
    var worksWeekends: Bool { self == .macek }

    /// Times a new shift starts out with, as minutes past midnight. Out of the
    /// box IJS is a day shift (08:00–16:00) and Maček an evening one
    /// (16:00–23:30); Settings can change either.
    var standardCheckInMinutes: Int {
        switch self {
        case .ijs: return 8 * 60
        case .macek: return 16 * 60
        }
    }

    var standardCheckOutMinutes: Int {
        switch self {
        case .ijs: return 16 * 60
        case .macek: return 23 * 60 + 30
        }
    }

    var defaultCheckInKey: String { "defaultCheckInMinutes.\(rawValue)" }
    var defaultCheckOutKey: String { "defaultCheckOutMinutes.\(rawValue)" }

    var defaultCheckIn: (hour: Int, minute: Int) {
        Self.split(UserDefaults.standard.object(forKey: defaultCheckInKey) as? Int ?? standardCheckInMinutes)
    }

    var defaultCheckOut: (hour: Int, minute: Int) {
        Self.split(UserDefaults.standard.object(forKey: defaultCheckOutKey) as? Int ?? standardCheckOutMinutes)
    }

    private static func split(_ minutes: Int) -> (hour: Int, minute: Int) {
        (minutes / 60, minutes % 60)
    }

    var tint: Color {
        switch self {
        case .ijs: return .blue
        case .macek: return .orange
        }
    }

    var symbol: String {
        switch self {
        case .ijs: return "chevron.left.forwardslash.chevron.right"
        case .macek: return "fork.knife"
        }
    }
}
