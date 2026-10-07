import SwiftUI
import SwiftData

/// One tab per job: repeat or log a shift, and this month at a glance. All-time
/// numbers and the projection live on Profile; the full history behind
/// "View all".
struct JobView: View {
    let job: Job

    @Environment(\.modelContext) private var context
    @Query(sort: \Shift.checkIn, order: .reverse) private var allShifts: [Shift]

    @State private var editorTarget: ShiftEditorTarget?
    @State private var pendingDelete: Shift?
    /// The shift the last tap on Repeat created, kept so it can be undone.
    @State private var repeatedShift: Shift?

    // MARK: - Derived data

    private var jobShifts: [Shift] {
        allShifts.filter { $0.job == job }
    }

    private var monthStats: ShiftStats {
        ShiftStats(job: job, shifts: StatsEngine.shifts(jobShifts, in: .month))
    }

    private var lastShift: Shift? { jobShifts.first }

    private var todayShift: Shift? {
        jobShifts.first { Calendar.current.isDateInToday($0.checkIn) }
    }

    var body: some View {
        NavigationStack {
            content
                // Still set, so View all's back button is named — but shown
                // in the list instead (see `content`).
                .navigationTitle(job.displayName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        // Keeps the small centred title out of the bar.
                        Color.clear.frame(width: 1, height: 1)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            editorTarget = .new(job)
                        } label: {
                            Label("Log shift", systemImage: "plus")
                        }
                    }
                }
                .sheet(item: $editorTarget) { target in
                    ShiftEditorView(target: target)
                }
                .confirmationDialog(
                    "Delete this shift?",
                    isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                    titleVisibility: .visible,
                    presenting: pendingDelete
                ) { shift in
                    Button("Delete", role: .destructive) {
                        context.delete(shift)
                        pendingDelete = nil
                    }
                    Button("Keep", role: .cancel) { pendingDelete = nil }
                } message: { shift in
                    Text("\(Fmt.dayHeader(shift.day)) · \(Fmt.time(shift.checkIn))–\(Fmt.time(shift.checkOut)) · \(Fmt.hours(shift.hours))")
                }
        }
    }

    // MARK: - Content

    private var content: some View {
        List {
            // The title as content rather than a large navigation title: that
            // one collapses to a small centred title as soon as a long tab is
            // scrolled. This one stays big and on the left, and scrolls away.
            Section {
                Text(job.displayName)
                    .font(.largeTitle.bold())
                    .lineLimit(1)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            if !jobShifts.isEmpty {
                Section {
                    MonthHeroCard(job: job, stats: monthStats)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                }
            }

            // Repeat is the only quick way in, so with nothing to repeat (and
            // no timer left running) there's no card at all.
            if lastShift != nil || ShiftClock.shared.running != nil {
                Section {
                    ClockCard(
                        job: job,
                        lastShift: lastShift,
                        todayShift: todayShift,
                        onClockOut: { checkIn, checkOut in
                            editorTarget = .clockedOut(job, checkIn: checkIn, checkOut: checkOut)
                        },
                        onRepeat: {
                            if let last = lastShift {
                                withAnimation(.snappy) { repeatLastShift(last) }
                            }
                        },
                        onUndo: repeatedShift != nil && repeatedShift === todayShift ? {
                            if let shift = repeatedShift {
                                withAnimation(.snappy) { context.delete(shift) }
                            }
                            repeatedShift = nil
                        } : nil
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                }
            }

            if jobShifts.isEmpty {
                Section {
                    emptyState
                }
            } else {
                Section {
                    WeekStrip(job: job, shifts: jobShifts) { day, shifts in
                        editorTarget = ShiftEditorTarget.forDay(day, job: job, shifts: shifts) ?? .edit(shifts[0])
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                }

                Section {
                    viewAllLink
                    NavigationLink {
                        TimesheetView(job: job, month: Calendar.current.startOfMonth(for: .now))
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Timesheet")
                                    .font(.body.weight(.semibold))
                                Text("\(Fmt.monthTitle(.now)) as a table, with the total")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "tablecells")
                                .foregroundStyle(job.tint)
                        }
                    }
                }

                shiftSection
            }
        }
        .listStyle(.insetGrouped)
        // The title row sits where the large title would, not a section gap below it.
        .contentMargins(.top, 0, for: .scrollContent)
        // Phone-sized: the default gap between sections wastes most of a screen
        // over this many cards.
        .listSectionSpacing(.compact)
        // Don't let a screen that already fits be dragged.
        .scrollBounceBehavior(.basedOnSize)
    }

    /// Same time of day and same length as the last shift, logged for today.
    private func repeatLastShift(_ last: Shift) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let parts = calendar.dateComponents([.hour, .minute], from: last.checkIn)
        let checkIn = calendar.date(
            bySettingHour: parts.hour ?? 0,
            minute: parts.minute ?? 0,
            second: 0,
            of: today
        ) ?? today
        // Carrying the duration rather than the clock time keeps overnight
        // shifts overnight.
        let shift = Shift(
            job: job,
            checkIn: checkIn,
            checkOut: checkIn.addingTimeInterval(last.checkOut.timeIntervalSince(last.checkIn))
        )
        context.insert(shift)
        repeatedShift = shift
    }

    /// Way into the full month-by-month history, sitting just above the
    /// recently logged shifts.
    private var viewAllLink: some View {
        NavigationLink {
            AllShiftsView(job: job)
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("View all")
                        .font(.body.weight(.semibold))
                    Text("Every day you've worked, month by month")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "calendar")
                    .foregroundStyle(job.tint)
            }
        }
    }

    private var shiftSection: some View {
        Section {
            if monthStats.shifts.isEmpty {
                Text("No shifts logged this month.")
                    .foregroundStyle(.secondary)
            } else {
                // One list with a date badge on each row reads quicker than a
                // header per day.
                ForEach(monthStats.shifts) { shift in
                    Button {
                        editorTarget = .edit(shift)
                    } label: {
                        ShiftRow(shift: shift)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button {
                            pendingDelete = shift
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
            }
        } header: {
            Text("Shifts this month")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No shifts yet", systemImage: job.symbol)
        } description: {
            Text("Log your first \(job.displayName) shift, at \(Fmt.money(job.hourlyRate))/h.")
        } actions: {
            Button("Log a shift") { editorTarget = .new(job) }
                .buttonStyle(.borderedProminent)
                .tint(job.tint)
        }
    }
}

/// One shift in the month's list: a date badge, the times, and what it paid.
struct ShiftRow: View {
    let shift: Shift

    var body: some View {
        HStack(spacing: 12) {
            DateBadge(date: shift.day, tint: shift.job.tint)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(Fmt.time(shift.checkIn)) → \(Fmt.time(shift.checkOut))")
                        .font(.body.weight(.medium))
                        .monospacedDigit()
                    if shift.isOvernight {
                        Text("+1")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                }
                HStack(spacing: 4) {
                    Text(Fmt.hours(shift.hours))
                    if shift.job.tracksTips, shift.tipsAmount > 0 {
                        Text("· \(Fmt.money(shift.tipsAmount)) tips")
                    }
                    if !shift.note.isEmpty {
                        Text("· \(shift.note)").lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(Fmt.money(shift.totalPay))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.green)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// "SAT / 4" in a tinted tile — the day a shift belongs to, at a glance.
struct DateBadge: View {
    let date: Date
    let tint: Color

    var body: some View {
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            Text(date.formatted(.dateTime.day()))
                .font(.title3.weight(.bold))
                .monospacedDigit()
        }
        .frame(width: 44, height: 44)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// This month's money up top, on the job's colour: the one number you open
/// the tab for, with the rest of the month underneath.
struct MonthHeroCard: View {
    let job: Job
    let stats: ShiftStats

    @AppStorage private var goalTarget: Double
    @AppStorage private var goalKindRaw: String

    init(job: Job, stats: ShiftStats) {
        self.job = job
        self.stats = stats
        _goalTarget = AppStorage(wrappedValue: 0, MonthlyGoal.targetKey(job))
        _goalKindRaw = AppStorage(wrappedValue: GoalKind.money.rawValue, MonthlyGoal.kindKey(job))
    }

    private var goalKind: GoalKind { GoalKind(rawValue: goalKindRaw) ?? .money }

    private var effectiveRate: Double {
        stats.totalHours > 0 ? stats.totalEarnings / stats.totalHours : job.hourlyRate
    }

    /// The darker end of the gradient, so the card has some depth.
    private var deepTint: Color {
        switch job {
        case .ijs: return Color(red: 0.25, green: 0.30, blue: 0.85)
        case .macek: return Color(red: 0.93, green: 0.33, blue: 0.22)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(Fmt.monthTitle(.now).uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                Spacer()
                Image(systemName: job.symbol)
            }
            .opacity(0.85)

            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.money(stats.totalEarnings))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(job.tracksTips
                     ? "earned incl. tips · ≈ \(Fmt.money(effectiveRate))/h"
                     : "earned · at \(Fmt.money(effectiveRate))/h")
                    .font(.subheadline)
                    .opacity(0.85)
            }

            if goalTarget > 0 {
                let now = goalKind.isMoney ? stats.totalEarnings : stats.totalHours
                VStack(alignment: .leading, spacing: 5) {
                    ProgressView(value: min(1, now / goalTarget))
                        .tint(.white)
                    Text("\(Int((now / goalTarget * 100).rounded()))% of the \(goalKind.isMoney ? Fmt.money(goalTarget) : Fmt.hours(goalTarget)) goal")
                        .font(.caption2.weight(.medium))
                        .opacity(0.85)
                }
            }

            HStack(spacing: 0) {
                heroStat("Hours", Fmt.hours(stats.totalHours))
                divider
                if job.tracksTips {
                    heroStat("Base pay", Fmt.money(stats.basePay))
                    divider
                    heroStat("Tips", Fmt.money(stats.totalTips))
                } else {
                    heroStat("Days", "\(stats.dayCount)")
                    divider
                    heroStat("Avg per day", Fmt.hours(stats.averageHoursPerDay))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [job.tint, deepTint], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private func heroStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .opacity(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.3))
            .frame(width: 1, height: 28)
            .padding(.trailing, 12)
    }
}

/// The seven days of the current week. Worked days are filled in; tapping a
/// day logs a shift there, or opens the one already logged.
struct WeekStrip: View {
    let job: Job
    let shifts: [Shift]
    let onSelect: (Date, [Shift]) -> Void

    private var calendar: Calendar { Calendar.current }

    private var days: [Date] {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: .now)?.start else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var shiftsByDay: [Date: [Shift]] {
        Dictionary(grouping: shifts.filter { days.contains($0.day) }, by: \.day)
    }

    private var weekHours: Double {
        shiftsByDay.values.joined().reduce(0) { $0 + $1.hours }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("This week")
                    .font(.headline)
                Spacer()
                Text(Fmt.hours(weekHours))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(job.tint)
            }

            HStack(spacing: 6) {
                ForEach(days, id: \.self) { day in
                    cell(day, shifts: shiftsByDay[day] ?? [])
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func cell(_ day: Date, shifts: [Shift]) -> some View {
        let hours = shifts.reduce(0) { $0 + $1.hours }
        let worked = !shifts.isEmpty
        let isToday = calendar.isDateInToday(day)

        return Button {
            onSelect(day, shifts)
        } label: {
            VStack(spacing: 3) {
                Text(day.formatted(.dateTime.weekday(.narrow)))
                    .font(.caption2.weight(.medium))
                    .opacity(worked ? 0.85 : 0.6)
                Text(day.formatted(.dateTime.day()))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                Text(worked ? Self.compactHours(hours) : "+")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(worked ? 0.9 : 0.4)
            }
            .foregroundStyle(worked ? Color.white : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                worked ? AnyShapeStyle(job.tint) : AnyShapeStyle(Color(.tertiarySystemFill)),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(worked ? Color.primary.opacity(0.35) : job.tint, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(worked ? "\(Fmt.dayInMonth(day)), \(Fmt.hours(hours))" : "\(Fmt.dayInMonth(day)), not worked")
        .accessibilityHint(worked ? "Edit shift" : "Log a shift")
    }

    /// "7.5h" — "7h 30m" doesn't fit a seventh of a phone.
    private static func compactHours(_ hours: Double) -> String {
        let rounded = (hours * 2).rounded() / 2
        return rounded == rounded.rounded() ? "\(Int(rounded))h" : String(format: "%.1fh", rounded)
    }
}

#Preview {
    JobView(job: .macek)
        .modelContainer(PreviewData.container)
}
