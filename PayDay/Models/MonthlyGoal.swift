import Foundation

/// What a monthly goal is measured in. The target itself is a per-job setting —
/// see `Job.goalTarget`.
enum GoalKind: String, CaseIterable, Identifiable, Codable {
    case money = "Earnings"
    case hours = "Hours"

    var id: String { rawValue }
    var isMoney: Bool { self == .money }
}
