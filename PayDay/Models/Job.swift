import SwiftUI
import SwiftData

/// One job you work. Everything that used to be a constant — the rate, the
/// colour, whether there are tips — belongs to the job now, so you can keep
/// as many as you like, each with its own tab.
///
/// The colour and symbol choices live in `JobAppearance.swift`.
@Model
final class Job {
    var id: UUID = UUID()
    var name: String = ""
    var colorRaw: String = JobColor.blue.rawValue
    var symbol: String = JobSymbol.fallback
    var hourlyRate: Double = 0
    /// A waiting job has tips; a desk job doesn't. Hides the tip fields when off.
    var tracksTips: Bool = false
    /// Whether weekend days count as workable when the month is projected.
    var worksWeekends: Bool = false
    /// Times a new shift starts out with, as minutes past midnight.
    var defaultCheckInMinutes: Int = 9 * 60
    var defaultCheckOutMinutes: Int = 17 * 60
    /// Position in the tab bar.
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    /// Monthly target, in the units of `goalKindRaw`. 0 means no goal. Kept
    /// on the job rather than in defaults so it syncs through iCloud with it.
    var goalTargetValue: Double = 0
    var goalKindRaw: String = GoalKind.money.rawValue

    // Inverses of `Shift.job` and `MonthPayment.job`. iCloud sync needs every
    // relationship to have one. Deleting a job goes through `AppSetup.delete`,
    // which removes its shifts first, so `.nullify` never orphans anything.
    @Relationship(deleteRule: .nullify, inverse: \Shift.job)
    var shifts: [Shift]? = []
    @Relationship(deleteRule: .nullify, inverse: \MonthPayment.job)
    var payments: [MonthPayment]? = []

    init(
        name: String,
        color: JobColor = .blue,
        symbol: String = JobSymbol.fallback,
        hourlyRate: Double,
        tracksTips: Bool = false,
        worksWeekends: Bool = false,
        defaultCheckInMinutes: Int = 9 * 60,
        defaultCheckOutMinutes: Int = 17 * 60,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.colorRaw = color.rawValue
        self.symbol = symbol
        self.hourlyRate = hourlyRate
        self.tracksTips = tracksTips
        self.worksWeekends = worksWeekends
        self.defaultCheckInMinutes = defaultCheckInMinutes
        self.defaultCheckOutMinutes = defaultCheckOutMinutes
        self.sortOrder = sortOrder
        self.createdAt = .now
    }

    // MARK: - Derived

    var jobColor: JobColor { JobColor(rawValue: colorRaw) ?? .blue }
    var tint: Color { jobColor.color }
    var gradientEnd: Color { jobColor.gradientEnd }

    /// What to show while the name is still blank.
    var displayName: String { name.isEmpty ? "Untitled job" : name }

    var defaultCheckIn: (hour: Int, minute: Int) {
        (defaultCheckInMinutes / 60, defaultCheckInMinutes % 60)
    }

    var defaultCheckOut: (hour: Int, minute: Int) {
        (defaultCheckOutMinutes / 60, defaultCheckOutMinutes % 60)
    }

    // MARK: - Per-job settings

    var goalTarget: Double {
        get { goalTargetValue }
        set { goalTargetValue = max(0, newValue) }
    }

    var goalKind: GoalKind {
        get { GoalKind(rawValue: goalKindRaw) ?? .money }
        set { goalKindRaw = newValue.rawValue }
    }

    /// Where the goal lived before it moved onto the job. Read once by
    /// `AppSetup` to carry an existing goal over.
    var legacyGoalTargetKey: String { "goalTarget.\(id.uuidString)" }
    var legacyGoalKindKey: String { "goalKind.\(id.uuidString)" }

    /// A view preference rather than data, so it stays on this phone.
    var projectionBasisKey: String { "projectionBasis.\(id.uuidString)" }

    /// Clears the job's phone-only preferences when it's deleted.
    func removeSettings() {
        let defaults = UserDefaults.standard
        for key in [legacyGoalTargetKey, legacyGoalKindKey, projectionBasisKey] {
            defaults.removeObject(forKey: key)
        }
    }
}
