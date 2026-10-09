import Foundation

/// Which slice of history the stats panel is showing.
enum StatsScope: String, CaseIterable, Identifiable {
    case month = "This month"
    case allTime = "All time"

    var id: String { rawValue }
}

/// How the remaining days of the current month are estimated for the pay projection.
enum ProjectionBasis: String, CaseIterable, Identifiable {
    /// Every remaining Mon–Fri that hasn't been logged yet.
    case weekdays = "Weekdays"
    /// Every remaining day, weekends included — a bar doesn't close on Sunday.
    case allDays = "Every day"
    /// Remaining days weighted by how often you actually work each day of the week.
    case pattern = "My pattern"

    var id: String { rawValue }

    var explanation: String {
        switch self {
        case .weekdays:
            return "Assumes you work every remaining weekday this month."
        case .allDays:
            return "Assumes you work every remaining day this month, weekends included."
        case .pattern:
            return "Weighs each remaining day by how often you work that weekday. Falls back to a plain count until there are two weeks of history."
        }
    }
}

/// One calendar day's worth of shifts, used for the grouped list and the day stats.
struct DayTotal: Identifiable {
    let date: Date
    var shifts: [Shift]

    var id: Date { date }
    var hours: Double { shifts.reduce(0) { $0 + $1.hours } }
    var tips: Double { shifts.reduce(0) { $0 + $1.tipsAmount } }
    var pay: Double { shifts.reduce(0) { $0 + $1.totalPay } }
}

/// One calendar month's worth of shifts, used by the full history list.
struct MonthTotal: Identifiable {
    /// First day of the month.
    let date: Date
    /// Days worked that month, newest first.
    var days: [DayTotal]

    var id: Date { date }

    /// Everything here is about shifts actually worked. Planned ones still
    /// appear in `days`, so the calendar can draw them, but they never reach
    /// a total.
    private var worked: [Shift] { days.flatMap(\.shifts).logged }

    var hours: Double { worked.reduce(0) { $0 + $1.hours } }
    var tips: Double { worked.reduce(0) { $0 + $1.tipsAmount } }
    var pay: Double { worked.reduce(0) { $0 + $1.totalPay } }
    var basePay: Double { pay - tips }

    var plannedHours: Double { days.flatMap(\.shifts).planned.reduce(0) { $0 + $1.hours } }

    var dayCount: Int { Set(worked.map(\.day)).count }
    var shiftCount: Int { worked.count }

    var averageHoursPerDay: Double {
        dayCount == 0 ? 0 : hours / Double(dayCount)
    }

    var longestDay: DayTotal? { days.max { $0.hours < $1.hours } }
}

/// Aggregate numbers for one job over one scope.
struct ShiftStats {
    let job: Job
    let shifts: [Shift]

    init(job: Job, shifts: [Shift]) {
        self.job = job
        self.shifts = shifts.sorted { $0.checkIn > $1.checkIn }
    }

    var totalHours: Double { shifts.reduce(0) { $0 + $1.hours } }
    var totalTips: Double { shifts.reduce(0) { $0 + $1.tipsAmount } }
    var basePay: Double { shifts.reduce(0) { $0 + $1.basePay } }
    var totalEarnings: Double { basePay + totalTips }

    var shiftCount: Int { shifts.count }

    /// Days grouped newest first.
    var days: [DayTotal] { StatsEngine.days(from: shifts) }

    var dayCount: Int { days.count }

    var averageHoursPerShift: Double {
        shiftCount == 0 ? 0 : totalHours / Double(shiftCount)
    }

    var averageHoursPerDay: Double {
        dayCount == 0 ? 0 : totalHours / Double(dayCount)
    }

    var averageTipsPerShift: Double {
        shiftCount == 0 ? 0 : totalTips / Double(shiftCount)
    }

    var averageTipsPerDay: Double {
        dayCount == 0 ? 0 : totalTips / Double(dayCount)
    }

    var longestDay: DayTotal? { days.max { $0.hours < $1.hours } }
}

/// Projected pay for the current month: what's already logged, plus the
/// remaining days of the month filled in at your average daily hours.
/// What the month is heading for, in three parts you can trust differently.
///
/// Worked is a fact. Planned is a rota you've entered, so it's nearly a fact.
/// Estimated is the app guessing from your habits, and is the only part worth
/// doubting — which is why the card shows them apart instead of adding them up
/// into one confident-looking number.
struct MonthProjection {
    let job: Job
    let basis: ProjectionBasis

    var hoursSoFar: Double
    /// Already-logged pay, at whatever rate each shift was logged at.
    var basePaySoFar: Double
    var tipsSoFar: Double
    /// Shifts entered for days still to come, not yet confirmed.
    var plannedHours: Double
    var plannedBasePay: Double
    var plannedTips: Double
    var averageHoursPerDay: Double
    var averageTipsPerDay: Double
    var daysWorked: Int
    var remainingDays: Double

    var payToDate: Double { basePaySoFar + tipsSoFar }
    var plannedPay: Double { plannedBasePay + plannedTips }

    /// Days the estimate still covers: whatever's left after the ones you've
    /// worked and the ones you've already planned.
    var estimatedDays: Double { max(0, remainingDays) }
    var estimatedHours: Double { averageHoursPerDay * estimatedDays }
    var estimatedTips: Double { averageTipsPerDay * estimatedDays }
    var estimatedBasePay: Double { estimatedHours * job.hourlyRate }
    var estimatedPay: Double { estimatedBasePay + estimatedTips }

    var projectedHours: Double { hoursSoFar + plannedHours + estimatedHours }
    var projectedTips: Double { tipsSoFar + plannedTips + estimatedTips }
    var projectedBasePay: Double { basePaySoFar + plannedBasePay + estimatedBasePay }
    var projectedTotal: Double { projectedBasePay + projectedTips }

    var hasPlan: Bool { plannedHours > 0 }

    /// `true` when there is nothing to extrapolate from and nothing planned.
    var isEmpty: Bool { daysWorked == 0 && !hasPlan }
}

enum StatsEngine {
    static var calendar: Calendar { Calendar.current }

    // MARK: - Filtering

    static func shifts(_ shifts: [Shift], for job: Job) -> [Shift] {
        shifts.filter { $0.job?.id == job.id }
    }

    static func shifts(_ shifts: [Shift], in scope: StatsScope, now: Date = .now) -> [Shift] {
        switch scope {
        case .allTime:
            return shifts
        case .month:
            return shifts.filter { calendar.isDate($0.checkIn, equalTo: now, toGranularity: .month) }
        }
    }

    // MARK: - Grouping

    /// Shifts grouped by the day they started, newest day first.
    static func days(from shifts: [Shift]) -> [DayTotal] {
        Dictionary(grouping: shifts, by: \.day)
            .map { DayTotal(date: $0.key, shifts: $0.value.sorted { $0.checkIn > $1.checkIn }) }
            .sorted { $0.date > $1.date }
    }

    /// Shifts grouped by calendar month, newest month first — the backbone of
    /// the full history list.
    static func months(from shifts: [Shift]) -> [MonthTotal] {
        Dictionary(grouping: shifts) { shift -> Date in
            calendar.date(from: calendar.dateComponents([.year, .month], from: shift.checkIn)) ?? shift.day
        }
        .map { MonthTotal(date: $0.key, days: days(from: $0.value)) }
        .sorted { $0.date > $1.date }
    }

    // MARK: - Projection

    static func projection(
        for job: Job,
        allShiftsForJob: [Shift],
        basis: ProjectionBasis,
        now: Date = .now
    ) -> MonthProjection {
        let monthShifts = shifts(allShiftsForJob, in: .month, now: now)
        let worked = monthShifts.logged
        let plan = monthShifts.planned

        let monthStats = ShiftStats(job: job, shifts: worked)
        let planStats = ShiftStats(job: job, shifts: plan)
        // The habit the estimate extrapolates from is built out of worked
        // shifts only. A rota you typed in says what you will do, not what
        // you usually do.
        let allTimeStats = ShiftStats(job: job, shifts: allShiftsForJob.logged)

        // Prefer this month's rhythm; fall back to all-time when the month is young.
        let avgHours = monthStats.dayCount >= 2 ? monthStats.averageHoursPerDay : allTimeStats.averageHoursPerDay
        let avgTips = monthStats.dayCount >= 2 ? monthStats.averageTipsPerDay : allTimeStats.averageTipsPerDay

        // A day that's worked or already planned needs no estimate.
        let spokenFor = Set(monthShifts.map(\.day))
        let remaining = remainingDays(
            for: job,
            basis: basis,
            loggedDays: spokenFor,
            allShiftsForJob: allShiftsForJob.logged,
            now: now
        )

        return MonthProjection(
            job: job,
            basis: basis,
            hoursSoFar: monthStats.totalHours,
            basePaySoFar: monthStats.basePay,
            tipsSoFar: monthStats.totalTips,
            plannedHours: planStats.totalHours,
            plannedBasePay: planStats.basePay,
            plannedTips: planStats.totalTips,
            averageHoursPerDay: avgHours,
            averageTipsPerDay: avgTips,
            daysWorked: monthStats.dayCount,
            remainingDays: remaining
        )
    }

    /// Days left in the current month that could still be worked.
    static func remainingDays(
        for job: Job,
        basis: ProjectionBasis,
        loggedDays: Set<Date>,
        allShiftsForJob: [Shift],
        now: Date = .now
    ) -> Double {
        let candidates = remainingCalendarDays(now: now).filter { !loggedDays.contains($0) }
        guard !candidates.isEmpty else { return 0 }

        let weekdayCount = Double(candidates.filter { isWeekday($0) }.count)
        let everyDayCount = Double(candidates.count)

        switch basis {
        case .weekdays:
            return weekdayCount
        case .allDays:
            return everyDayCount
        case .pattern:
            // Without enough history to profile a week, fall back to whatever
            // "all the days you could work" means for this job — Mon–Fri at the
            // institute, any day at the bar.
            let plain = job.worksWeekends ? everyDayCount : weekdayCount
            return expectedRemainingDays(candidates: candidates, shifts: allShiftsForJob, now: now) ?? plain
        }
    }

    /// Today through the last day of the month, as start-of-day dates.
    private static func remainingCalendarDays(now: Date) -> [Date] {
        let today = calendar.startOfDay(for: now)
        guard let range = calendar.range(of: .day, in: .month, for: now),
              let monthStart = calendar.dateInterval(of: .month, for: now)?.start,
              let monthEnd = calendar.date(byAdding: .day, value: range.count - 1, to: monthStart)
        else { return [] }

        var days: [Date] = []
        var cursor = today
        while cursor <= calendar.startOfDay(for: monthEnd) {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    private static func isWeekday(_ date: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday != 1 && weekday != 7 // not Sunday, not Saturday
    }

    /// Expected number of days still to be worked, weighted per weekday: a job
    /// worked only on Fri/Sat shouldn't be projected across every weekday.
    ///
    /// Each remaining day contributes `times that weekday was worked / times it
    /// occurred`. Returns `nil` when there is under two weeks of history, which
    /// is too little to profile a week.
    private static func expectedRemainingDays(candidates: [Date], shifts: [Shift], now: Date) -> Double? {
        let workedDays = Set(shifts.map(\.day))
        guard let first = workedDays.min() else { return nil }

        // Observe up to yesterday: today is still in progress and would count as a miss.
        let today = calendar.startOfDay(for: now)
        guard let lastObserved = calendar.date(byAdding: .day, value: -1, to: today), first <= lastObserved else { return nil }
        let span = (calendar.dateComponents([.day], from: first, to: lastObserved).day ?? 0) + 1
        guard span >= 14 else { return nil }

        var occurrences: [Int: Int] = [:]
        var worked: [Int: Int] = [:]
        var cursor = first
        while cursor <= lastObserved {
            let weekday = calendar.component(.weekday, from: cursor)
            occurrences[weekday, default: 0] += 1
            if workedDays.contains(cursor) { worked[weekday, default: 0] += 1 }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return candidates.reduce(0.0) { total, day in
            let weekday = calendar.component(.weekday, from: day)
            guard let occurred = occurrences[weekday], occurred > 0 else { return total }
            return total + min(1, Double(worked[weekday] ?? 0) / Double(occurred))
        }
    }

    // MARK: - Profile buckets

    /// Hours and earnings per job, bucketed by week or month, oldest first.
    static func buckets(
        from shifts: [Shift],
        jobs: [Job],
        granularity: Calendar.Component,
        limit: Int,
        now: Date = .now
    ) -> [Bucket] {
        let component: Set<Calendar.Component> = granularity == .weekOfYear
            ? [.yearForWeekOfYear, .weekOfYear]
            : [.year, .month]

        let grouped = Dictionary(grouping: shifts) { shift -> Date in
            calendar.date(from: calendar.dateComponents(component, from: shift.checkIn)) ?? shift.day
        }

        let recentStarts = grouped.keys.sorted().suffix(limit)

        return recentStarts.map { start in
            let entries = grouped[start] ?? []
            return Bucket(
                start: start,
                granularity: granularity,
                perJob: Dictionary(uniqueKeysWithValues: jobs.map { job in
                    let jobShifts = entries.filter { $0.job?.id == job.id }
                    return (job.id, JobBucketValue(
                        hours: jobShifts.reduce(0) { $0 + $1.hours },
                        earnings: jobShifts.reduce(0) { $0 + $1.totalPay }
                    ))
                })
            )
        }
    }

    struct JobBucketValue {
        var hours: Double
        var earnings: Double
    }

    struct Bucket: Identifiable {
        let start: Date
        let granularity: Calendar.Component
        var perJob: [UUID: JobBucketValue]

        var id: Date { start }

        var label: String {
            granularity == .weekOfYear ? Fmt.shortDay(start) : Fmt.shortMonth(start)
        }

        func value(for job: Job, metric: ProfileMetric) -> Double {
            let entry = perJob[job.id] ?? JobBucketValue(hours: 0, earnings: 0)
            return metric == .hours ? entry.hours : entry.earnings
        }
    }
}

enum ProfileMetric: String, CaseIterable, Identifiable {
    case hours = "Hours"
    case earnings = "Earnings"

    var id: String { rawValue }
}
