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
        ShiftStats(job: job, shifts: StatsEngine.shifts(jobShifts, in: .month).logged)
    }

    /// The shift Repeat would copy. A plan isn't a precedent, so only worked
    /// ones count.
    private var lastShift: Shift? { jobShifts.logged.first }

    /// Only a confirmed shift counts as "logged today" — a plan for this
    /// evening is still a plan at nine in the morning.
    private var todayShift: Shift? {
        jobShifts.logged.first { Calendar.current.isDateInToday($0.checkIn) }
    }

    var body: some View {
        NavigationStack {
            content
                // Still set, so View all's back button is named — but shown
                // in the list instead (see `content`).
                .navigationTitle(job.displayName)
                .navigationBarTitleDisplayMode(.inline)
                // No bar at all: the title and the + are a row of content, so
                // an empty bar above them was only taking height.
                .toolbar(.hidden, for: .navigationBar)
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
                HStack {
                    Text(job.displayName)
                        .font(.largeTitle.bold())
                        // A grouped list clips each row at the card's edge,
                        // and a rounded "g" or "j" at this size hangs well
                        // past the left of its typographic box — the tail was
                        // being sliced off. Indenting the text keeps the whole
                        // glyph inside the clip.
                        .padding(.leading, 10)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Spacer(minLength: 12)

                    Button {
                        editorTarget = .new(job)
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(job.tint)
                            .frame(width: 38, height: 38)
                            .background(job.tint.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Log shift")
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 1, bottom: 0, trailing: 4))
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
                    .listRowSeparator(.hidden)
                }

                Section {
                    viewAllLink
                        .listRowBackground(TintedRow(colour: job.tint))
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
                    .listRowBackground(TintedRow(colour: job.tint))
                }

                plannedSection
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

    private var plannedShifts: [Shift] {
        jobShifts.planned
            .filter { $0.checkIn > Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now }
            .sorted { $0.checkIn < $1.checkIn }
    }

    @ViewBuilder
    private var plannedSection: some View {
        if !plannedShifts.isEmpty {
            Section {
                ForEach(plannedShifts) { shift in
                    PlannedRow(shift: shift, job: job) {
                        confirm(shift)
                    } onEdit: {
                        editorTarget = .edit(shift, job)
                    }
                    .listRowBackground(TintedRow(colour: job.tint))
                    .swipeActions(edge: .trailing) {
                        Button {
                            pendingDelete = shift
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
            } header: {
                SectionHeader("Planned")
            } footer: {
                Text("Planned shifts count toward the projection, never toward what you've earned. Confirm one once you've worked it.")
            }
        }
    }

    /// Turns a plan into a fact. Nothing else changes — the times stay as
    /// planned, and you can still open it to correct them.
    private func confirm(_ shift: Shift) {
        withAnimation(.snappy) { shift.isPlanned = false }
        Haptics.success()
    }

    private var shiftSection: some View {
        Section {
            if monthStats.shifts.isEmpty {
                Text("No shifts logged this month.")
                    .foregroundStyle(.secondary)
                    .listRowBackground(TintedRow(colour: job.tint))
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
                    .listRowBackground(TintedRow(colour: job.tint))
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
            SectionHeader("Worked this month")
        }
    }

    private var emptyState: some View {
        EmptyState(
            symbol: job.symbol,
            title: "No shifts yet",
            message: "Log your first \(job.displayName) shift and this tab fills in — hours, pay and what the month is heading for.",
            tint: job.tint,
            actionTitle: "Log a shift",
            action: { editorTarget = .new(job) }
        )
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
    /// Dashed rather than filled, for a day that hasn't happened yet.
    var outlined = false

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
        .background(tint.opacity(outlined ? 0.06 : 0.12),
                    in: RoundedRectangle(cornerRadius: Palette.tileRadius, style: .continuous))
        .overlay {
            if outlined {
                RoundedRectangle(cornerRadius: Palette.tileRadius, style: .continuous)
                    .strokeBorder(tint, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
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

    /// Weeks away from this one. Negative is the past, positive the future —
    /// which is how you reach a day you haven't worked yet.
    @State private var offset = 0
    /// A week at a time, or the whole month laid out. The week is the default
    /// because it's what you act on; the month is for seeing the shape of it.
    @AppStorage("stripShowsMonth") private var showsMonth = false

    /// How far either way you can page. Two years covers anything useful and
    /// keeps the pager from building an unbounded number of pages.
    private static let range = -104...104

    private var calendar: Calendar { Calendar.current }

    private func weekStart(_ week: Int) -> Date {
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return calendar.date(byAdding: .weekOfYear, value: week, to: thisWeek) ?? thisWeek
    }

    private func days(_ week: Int) -> [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart(week)) }
    }

    private var weekStart: Date { weekStart(offset) }
    private var days: [Date] { days(offset) }

    /// "This week", "Next week", or the dates when it's further out.
    private var title: String {
        if showsMonth {
            switch offset {
            case 0: return "This month"
            case 1: return "Next month"
            case -1: return "Last month"
            default: return Fmt.monthTitle(monthStart(offset))
            }
        }
        switch offset {
        case 0: return "This week"
        case 1: return "Next week"
        case -1: return "Last week"
        default:
            guard let end = days.last else { return "" }
            let sameMonth = calendar.isDate(weekStart, equalTo: end, toGranularity: .month)
            let from = weekStart.formatted(sameMonth
                ? .dateTime.day()
                : .dateTime.day().month(.abbreviated))
            return "\(from) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
        }
    }

    /// Start of the month `step` months from this one.
    private func monthStart(_ step: Int) -> Date {
        let thisMonth = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        return calendar.date(byAdding: .month, value: step, to: thisMonth) ?? thisMonth
    }

    /// Hours in whichever span is on screen.
    private var spanHours: Double {
        let span: Set<Date>
        if showsMonth {
            span = Set(monthCells(offset).compactMap { $0 })
        } else {
            span = Set(days)
        }
        return shifts.filter { span.contains($0.day) }.reduce(0) { $0 + $1.hours }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                step(-1, "chevron.left")

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline)
                        .contentTransition(.numericText())
                    if offset != 0 {
                        Button(showsMonth ? "Back to this month" : "Back to this week") {
                            withAnimation(.snappy) { offset = 0 }
                        }
                        .font(.caption2)
                        .buttonStyle(.plain)
                        .foregroundStyle(job.tint)
                    }
                }

                Spacer()

                Text(Fmt.hours(spanHours))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(job.tint)
                    .contentTransition(.numericText())

                step(1, "chevron.right")

                Button {
                    withAnimation(.snappy) {
                        showsMonth.toggle()
                        offset = 0
                    }
                } label: {
                    Image(systemName: showsMonth ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(job.tint)
                        .frame(width: 28, height: 28)
                        .background(job.tint.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showsMonth ? "Show the week" : "Show the month")
            }

            TabView(selection: $offset) {
                ForEach(Array(Self.range), id: \.self) { step in
                    Group {
                        if showsMonth {
                            monthGrid(step)
                        } else {
                            HStack(spacing: 6) {
                                ForEach(days(step), id: \.self) { day in
                                    cell(day, shifts: shifts(on: day))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .tag(step)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: showsMonth ? 320 : 68)
        }
        .washedCard(job.tint, strength: 0.09, padding: 14)
    }

    /// Leading blanks so the 1st lands under the right weekday.
    private func monthCells(_ step: Int) -> [Date?] {
        let month = monthStart(step)
        guard let count = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let weekday = calendar.component(.weekday, from: month)
        let lead = (weekday - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: lead)
        for offset in 0..<count {
            cells.append(calendar.date(byAdding: .day, value: offset, to: month))
        }
        return cells
    }

    private func monthGrid(_ step: Int) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        return VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(monthCells(step).enumerated()), id: \.offset) { _, day in
                    if let day {
                        cell(day, shifts: shifts(on: day), compact: true)
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    private func shifts(on day: Date) -> [Shift] {
        shifts.filter { $0.day == day }
    }

    private func step(_ by: Int, _ symbol: String) -> some View {
        Button {
            withAnimation(.snappy) { offset += by }
        } label: {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .foregroundStyle(job.tint)
                .frame(width: 28, height: 28)
                .background(job.tint.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(by > 0 ? "Next week" : "Previous week")
    }

    private func cell(_ day: Date, shifts: [Shift], compact: Bool = false) -> some View {
        let hours = shifts.reduce(0) { $0 + $1.hours }
        let planned = !shifts.isEmpty && shifts.allSatisfy(\.isPlanned)
        let worked = !shifts.isEmpty && !planned
        let isToday = calendar.isDateInToday(day)

        return Button {
            onSelect(day, shifts)
        } label: {
            VStack(spacing: compact ? 1 : 3) {
                if !compact {
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2.weight(.medium))
                        .opacity(worked ? 0.85 : 0.6)
                }
                Text(day.formatted(.dateTime.day()))
                    .font(compact ? .caption.weight(.semibold) : .callout.weight(.semibold))
                    .monospacedDigit()
                Text(shifts.isEmpty ? "+" : Self.compactHours(hours))
                    .font(.system(size: compact ? 9 : 10, weight: .semibold))
                    .opacity(shifts.isEmpty ? 0.4 : 0.9)
            }
            .foregroundStyle(worked ? Color.white : (planned ? job.tint : .primary))
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 40 : nil)
            .padding(.vertical, compact ? 0 : 8)
            .background(
                worked ? AnyShapeStyle(job.tint)
                       : AnyShapeStyle(planned ? job.tint.opacity(0.10) : Color(.tertiarySystemFill)),
                in: RoundedRectangle(cornerRadius: Palette.tileRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Palette.tileRadius, style: .continuous)
                    .strokeBorder(job.tint,
                                  style: StrokeStyle(lineWidth: planned ? 1.5 : 2,
                                                     dash: planned ? [4, 3] : []))
                    .opacity(planned ? 1 : (isToday && !worked ? 1 : 0))
            }
            .overlay {
                if isToday && worked {
                    RoundedRectangle(cornerRadius: Palette.tileRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.35), lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(shifts.isEmpty
            ? "\(Fmt.dayInMonth(day)), nothing"
            : "\(Fmt.dayInMonth(day)), \(Fmt.hours(hours))\(planned ? ", planned" : "")")
        .accessibilityHint(shifts.isEmpty ? "Log a shift" : "Edit shift")
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
                // Across rather than down, and lighter: the hero card directly
                // above already washes this colour from the top, and two of
                // those in a row read as one tall card.
                .washedCard(job.tint, strength: 0.14, padding: 14, from: .leading, to: .trailing)
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


/// A shift you've entered but not yet worked. Outlined rather than filled, so
/// it reads as a promise; the tick is how it becomes a fact.
struct PlannedRow: View {
    let shift: Shift
    let job: Job
    let onConfirm: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onEdit) {
                HStack(spacing: 12) {
                    DateBadge(date: shift.day, tint: job.tint, outlined: true)

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
                        Text(shift.isOverdue
                             ? "Did you work this?"
                             : "\(Fmt.hours(shift.hours)) · \(Fmt.money(shift.totalPay)) when confirmed")
                            .font(.caption)
                            .foregroundStyle(shift.isOverdue ? Palette.attention : .secondary)
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onConfirm) {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(job.tint, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Confirm this shift")
        }
        .padding(.vertical, 2)
    }
}
