import ActivityKit
import Foundation
import Observation

/// A shift that's running right now. Survives quitting the app, so closing it
/// mid-shift doesn't lose your check-in time.
struct RunningShift: Codable, Equatable {
    var jobRaw: String
    var startedAt: Date

    var job: Job { Job(rawValue: jobRaw) ?? .ijs }

    func elapsedHours(now: Date = .now) -> Double {
        max(0, now.timeIntervalSince(startedAt)) / 3600
    }

    func earned(now: Date = .now) -> Double {
        elapsedHours(now: now) * job.hourlyRate
    }
}

/// Clocking in and out, plus the Live Activity that mirrors it on the Lock
/// Screen.
///
/// Only one shift runs at a time — you can't wait tables and write code at the
/// same minute, and pretending otherwise would double-count the hours.
@Observable
final class ShiftClock {
    static let shared = ShiftClock()

    private(set) var running: RunningShift?

    @ObservationIgnored private var activity: Activity<ShiftActivityAttributes>?
    @ObservationIgnored private let storageKey = "runningShift"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(RunningShift.self, from: data) {
            running = saved
        }
        // Reconnect to an activity that outlived the last launch.
        activity = Activity<ShiftActivityAttributes>.activities.first
        if running == nil { endActivity() }
    }

    func isRunning(_ job: Job) -> Bool {
        running?.job == job
    }

    // MARK: - Clocking

    func start(_ job: Job, at date: Date = .now) {
        guard running == nil else { return }
        let shift = RunningShift(jobRaw: job.rawValue, startedAt: date)
        running = shift
        persist()
        startActivity(for: shift)
    }

    /// Stops the clock and hands back the times to log. Returns `nil` if
    /// nothing was running.
    @discardableResult
    func stop(at date: Date = .now) -> (checkIn: Date, checkOut: Date)? {
        guard let shift = running else { return nil }
        running = nil
        persist()
        endActivity()
        return (shift.startedAt, max(date, shift.startedAt))
    }

    /// Throws the running shift away without logging it.
    func discard() {
        running = nil
        persist()
        endActivity()
    }

    private func persist() {
        if let running, let data = try? JSONEncoder().encode(running) {
            UserDefaults.standard.set(data, forKey: storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
    }

    // MARK: - Live Activity

    private func startActivity(for shift: RunningShift) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = ShiftActivityAttributes(
            jobRaw: shift.jobRaw,
            startedAt: shift.startedAt,
            hourlyRate: shift.job.hourlyRate
        )
        let state = ShiftActivityAttributes.ContentState(earnedSoFar: 0, asOf: .now)
        activity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil)
        )
    }

    /// Pushes a fresh pay figure into the activity. The elapsed timer ticks by
    /// itself; the € amount only moves when we get a chance to update it.
    func refreshActivity() {
        guard let running, let activity else { return }
        let state = ShiftActivityAttributes.ContentState(
            earnedSoFar: running.earned(),
            asOf: .now
        )
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    private func endActivity() {
        guard let activity else { return }
        self.activity = nil
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
