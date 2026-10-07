import Foundation

/// What a monthly goal is measured in.
enum GoalKind: String, CaseIterable, Identifiable, Codable {
    case money = "Earnings"
    case hours = "Hours"

    var id: String { rawValue }
    var isMoney: Bool { self == .money }
}

/// Per-job monthly target. Lives in defaults rather than the store — it's a
/// setting, not history.
enum MonthlyGoal {
    static func targetKey(_ job: Job) -> String { "goalTarget.\(job.rawValue)" }
    static func kindKey(_ job: Job) -> String { "goalKind.\(job.rawValue)" }

    /// 0 means no goal set.
    static func target(for job: Job) -> Double {
        UserDefaults.standard.double(forKey: targetKey(job))
    }

    static func kind(for job: Job) -> GoalKind {
        GoalKind(rawValue: UserDefaults.standard.string(forKey: kindKey(job)) ?? "") ?? .money
    }

    /// How far along you are, or `nil` when there's no goal to measure against.
    static func progress(for job: Job, hours: Double, earned: Double) -> Double? {
        let target = target(for: job)
        guard target > 0 else { return nil }
        return (kind(for: job).isMoney ? earned : hours) / target
    }
}
