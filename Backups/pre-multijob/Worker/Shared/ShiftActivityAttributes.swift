import ActivityKit
import Foundation

/// The payload behind the Lock Screen activity that runs for as long as you're
/// clocked in.
///
/// `startedAt` lives in the attributes because it never changes — the elapsed
/// time on screen is drawn with `Text(timerInterval:)`, which ticks on its own
/// without the app having to push updates. Pay can't be expressed that way, so
/// `earnedSoFar` is a snapshot the app refreshes when it gets the chance.
struct ShiftActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var earnedSoFar: Double
        var asOf: Date
    }

    var jobRaw: String
    var startedAt: Date
    var hourlyRate: Double

    var job: Job { Job(rawValue: jobRaw) ?? .ijs }
}
