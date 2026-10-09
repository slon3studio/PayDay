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
        allShifts.filter { $0.job?.id == job.id }
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

            // Repeat is the one quick way in, so with nothing to repeat there's
            // no card at all.
            if lastShift != nil {
                Section {
                    RepeatCard(
                        job: job,
                        lastShift: lastShift,
                        todayShift: todayShift,
                        onRepeat: {
                            if let last = lastShift {
                                withAnimation(.snappy) { repeatLastShift(last) }
                            }
                        },
                        onUndo: repeatedShift != nil && repeatedShift === todayShift ? {
                            if let shift = repeatedShift {
                                withAnimation(.snappy) { context.delete(shift) }
                                Haptics.tap()
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
                        editorTarget = ShiftEditorTarget.forDay(day, job: job, shifts: shifts) ?? .edit(shifts[0], job)
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
        Haptics.success()
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
                        editorTarget = .edit(shift, job)
                    } label: {
                        ShiftRow(shift: shift, job: job)
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
    let job: Job

    var body: some View {
        HStack(spacing: 12) {
            DateBadge(date: shift.day, tint: job.tint)

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
                    if job.tracksTips, shift.tipsAmount > 0 {
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
                .foregroundStyle(Palette.money)
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

    private var goalTarget: Double { job.goalTarget }
    private var goalKind: GoalKind { job.goalKind }

    private var effectiveRate: Double {
        stats.totalHours > 0 ? stats.totalEarnings / stats.totalHours : job.hourlyRate
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
            LinearGradient(colors: [job.tint, job.gradientEnd], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous)
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
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous))
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
                in: RoundedRectangle(cornerRadius: Palette.tileRadius, style: .continuous)
            )
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: Palette.tileRadius, style: .continuous)
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

/// Log the same shift as last time, for today — or, once today is logged,
/// say so, with a way to take a mis-tap back.
struct RepeatCard: View {
    let job: Job
    /// The shift "repeat" would copy, or `nil` when there's nothing logged yet.
    let lastShift: Shift?
    /// Today's shift once there is one — repeating again would just log a
    /// duplicate, so the button gives way to a confirmation.
    let todayShift: Shift?
    let onRepeat: () -> Void
    /// Set only right after a repeat, so a mis-tap can be taken back.
    var onUndo: (() -> Void)? = nil

    var body: some View {
        if let today = todayShift {
            loggedToday(today)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous))
        } else if let last = lastShift {
            Button(action: onRepeat) {
                // Plain text, not a Label: the button hides the icon but keeps
                // its space, which pushed the title off centre.
                Text("Repeat \(Fmt.time(last.checkIn)) → \(Fmt.time(last.checkOut))")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .tint(job.tint)
        }
    }

    private func loggedToday(_ shift: Shift) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(Palette.money)
            VStack(alignment: .leading, spacing: 2) {
                Text("Logged today")
                    .font(.headline)
                Text("\(Fmt.time(shift.checkIn)) → \(Fmt.time(shift.checkOut)) · \(Fmt.hours(shift.hours))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            if let onUndo {
                Button("Undo", action: onUndo)
                    .buttonStyle(.bordered)
                    .tint(job.tint)
            }
        }
    }
}

#Preview {
    JobView(job: Job(name: "M🐱ček", color: .orange, symbol: "fork.knife", hourlyRate: 9, tracksTips: true))
        .modelContainer(PreviewData.container)
}
