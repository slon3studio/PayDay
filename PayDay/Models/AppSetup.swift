import Foundation
import SwiftData

/// Carries a store written by the two-job version of this app — IJS and
/// Maček as fixed tabs — over to the one where jobs are yours to add, once,
/// on the first launch after the update.
///
/// The schema change itself is one SwiftData can do unaided: `Job` is a new
/// entity, and `Shift.job` / `MonthPayment.job` are *optional*. What's left is
/// turning the two old jobs into real ones and pointing every old row at the
/// right one, which is what this does.
///
/// Keyed off "are there no jobs yet, but there is history" — so it runs
/// exactly once, and never on a fresh install.
@MainActor
enum AppSetup {

    /// The two jobs the app used to have built in, with everything that was
    /// hard-coded about them, and the per-job settings keys they used.
    private struct LegacyJob {
        let raw: String
        let name: String
        let color: JobColor
        let symbol: String
        let originalRate: Double
        let tracksTips: Bool
        let worksWeekends: Bool
        let checkIn: Int
        let checkOut: Int

        static let all = [
            LegacyJob(raw: "ijs", name: "IJS 👨‍💻", color: .blue,
                      symbol: "chevron.left.forwardslash.chevron.right",
                      originalRate: 9.25, tracksTips: false, worksWeekends: false,
                      checkIn: 8 * 60, checkOut: 16 * 60),
            LegacyJob(raw: "macek", name: "M🐱ček", color: .orange, symbol: "fork.knife",
                      originalRate: 9.00, tracksTips: true, worksWeekends: true,
                      checkIn: 16 * 60, checkOut: 23 * 60 + 30),
        ]

        var rateKey: String { "hourlyRate.\(raw)" }
        var checkInKey: String { "defaultCheckInMinutes.\(raw)" }
        var checkOutKey: String { "defaultCheckOutMinutes.\(raw)" }
        var goalTargetKey: String { "goalTarget.\(raw)" }
        var goalKindKey: String { "goalKind.\(raw)" }
        var basisKey: String { "projectionBasis.\(raw)" }
    }

    static func migrateIfNeeded(_ context: ModelContext) {
        let jobs = (try? context.fetch(FetchDescriptor<Job>())) ?? []
        moveGoalsOntoJobs(jobs, in: context)
        guard jobs.isEmpty else { return }

        // Only rows written by the two-job version are migrated, and those are
        // exactly the ones carrying a `jobRaw`. Anything logged since has an
        // empty one.
        //
        // The test used to be "there are no jobs but there is history", which
        // is true in one state that has nothing to do with upgrading: a device
        // part-way through its first iCloud sync, where the shifts have landed
        // and the jobs haven't yet. Launching then would have invented IJS and
        // Maček for someone who has never heard of either.
        let shifts = ((try? context.fetch(FetchDescriptor<Shift>())) ?? [])
            .filter { !$0.jobRaw.isEmpty }
        let payments = ((try? context.fetch(FetchDescriptor<MonthPayment>())) ?? [])
            .filter { !$0.jobRaw.isEmpty }

        // A fresh install has nothing to carry over — it gets the onboarding
        // screen and adds its own jobs.
        guard !shifts.isEmpty || !payments.isEmpty else { return }

        let defaults = UserDefaults.standard
        var byRaw: [String: (job: Job, legacy: LegacyJob)] = [:]

        for (index, legacy) in LegacyJob.all.enumerated() {
            let savedRate = defaults.double(forKey: legacy.rateKey)
            let job = Job(
                name: legacy.name,
                color: legacy.color,
                symbol: legacy.symbol,
                hourlyRate: savedRate > 0 ? savedRate : legacy.originalRate,
                tracksTips: legacy.tracksTips,
                worksWeekends: legacy.worksWeekends,
                defaultCheckInMinutes: defaults.object(forKey: legacy.checkInKey) as? Int ?? legacy.checkIn,
                defaultCheckOutMinutes: defaults.object(forKey: legacy.checkOutKey) as? Int ?? legacy.checkOut,
                sortOrder: index
            )
            let goal = defaults.double(forKey: legacy.goalTargetKey)
            if goal > 0 { job.goalTarget = goal }
            if let kind = defaults.string(forKey: legacy.goalKindKey).flatMap(GoalKind.init(rawValue:)) {
                job.goalKind = kind
            }
            context.insert(job)
            byRaw[legacy.raw] = (job, legacy)
        }

        for shift in shifts where shift.job == nil {
            guard let match = byRaw[shift.jobRaw] else { continue }
            shift.job = match.job
            // Freeze what the shift was actually being paid at. Without this
            // it would silently re-price itself whenever the job's rate moves.
            if shift.rate == nil { shift.rate = match.legacy.originalRate }
        }

        for payment in payments where payment.job == nil {
            payment.job = byRaw[payment.jobRaw]?.job
        }

        try? context.save()

        // Only once the save went through. The projection basis is a view
        // preference and stays on the phone, under the job's new key.
        for (job, legacy) in byRaw.values {
            if let basis = defaults.string(forKey: legacy.basisKey) {
                defaults.set(basis, forKey: job.projectionBasisKey)
            }
            for key in [legacy.rateKey, legacy.checkInKey, legacy.checkOutKey,
                        legacy.goalTargetKey, legacy.goalKindKey, legacy.basisKey] {
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// Goals used to be kept per job in defaults, where iCloud can't reach
    /// them. Moves any still there onto their job. Safe to run every launch.
    private static func moveGoalsOntoJobs(_ jobs: [Job], in context: ModelContext) {
        let defaults = UserDefaults.standard
        var moved = false
        for job in jobs {
            let target = defaults.double(forKey: job.legacyGoalTargetKey)
            if target > 0 {
                job.goalTarget = target
                moved = true
            }
            if let kind = defaults.string(forKey: job.legacyGoalKindKey) {
                if let goalKind = GoalKind(rawValue: kind) { job.goalKind = goalKind }
                moved = true
            }
        }
        guard moved else { return }
        try? context.save()
        for job in jobs {
            defaults.removeObject(forKey: job.legacyGoalTargetKey)
            defaults.removeObject(forKey: job.legacyGoalKindKey)
        }
    }

    /// Deleting a job takes its shifts and payments with it. Done by hand
    /// rather than with a cascade rule, so the relationship can stay a plain
    /// optional and the migration above stays a lightweight one.
    static func delete(_ job: Job, in context: ModelContext) {
        let jobID = job.id
        let shifts = (try? context.fetch(FetchDescriptor<Shift>())) ?? []
        for shift in shifts where shift.job?.id == jobID {
            context.delete(shift)
        }
        let payments = (try? context.fetch(FetchDescriptor<MonthPayment>())) ?? []
        for payment in payments where payment.job?.id == jobID {
            context.delete(payment)
        }
        job.removeSettings()
        context.delete(job)
        try? context.save()
    }
}
