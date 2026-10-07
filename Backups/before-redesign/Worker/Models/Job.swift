import SwiftUI

/// The two jobs tracked by the app.
enum Job: String, CaseIterable, Codable, Identifiable {
    case ijs
    case macek

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ijs: return "IJS"
        case .macek: return "Maček"
        }
    }

    var subtitle: String {
        switch self {
        case .ijs: return "Programming"
        case .macek: return "Waiting tables"
        }
    }

    var hourlyRate: Double {
        switch self {
        case .ijs: return 9.25
        case .macek: return 9.00
        }
    }

    /// Only the waiter job records tips.
    var tracksTips: Bool { self == .macek }

    /// Whether weekend shifts are on the table. The institute is Mon–Fri; a bar
    /// very much isn't, so projecting Maček across weekdays only undercounts it.
    var worksWeekends: Bool { self == .macek }

    /// Times a new shift starts out with: the usual shift for this job.
    /// IJS is a day shift (08:00–16:00), Maček an evening one (16:00–23:30).
    var defaultCheckIn: (hour: Int, minute: Int) {
        switch self {
        case .ijs: return (8, 0)
        case .macek: return (16, 0)
        }
    }

    var defaultCheckOut: (hour: Int, minute: Int) {
        switch self {
        case .ijs: return (16, 0)
        case .macek: return (23, 30)
        }
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
