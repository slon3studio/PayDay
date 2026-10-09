import SwiftUI
import SwiftData

/// The full history for one job: every month you've worked, collapsible, with
/// the days inside it. A day shows its date and hours; opening it reveals the
/// check-in/check-out times, pay, tips and note for each shift on that day.
struct AllShiftsView: View {
    let job: Job

    @Environment(\.modelContext) private var context
    @Query(sort: \Shift.checkIn, order: .reverse) private var allShifts: [Shift]
    @Query private var payments: [MonthPayment]

    @State private var expandedMonths: Set<Date> = []
    @State private var expandedDays: Set<Date> = []
    @State private var editorTarget: ShiftEditorTarget?
    @State private var pendingDelete: Shift?
    @State private var payTarget: MonthTotal?
    @State private var didSeedExpansion = false

    // MARK: - Derived data

    private var jobShifts: [Shift] {
        allShifts.filter { $0.job?.id == job.id }
    }

    /// Every month worked, plus the current one even before its first shift,
    /// so its calendar is there to tap a day into.
    private var months: [MonthTotal] {
        var months = StatsEngine.months(from: jobShifts)
        let calendar = Calendar.current
        if let thisMonth = calendar.dateInterval(of: .month, for: .now)?.start,
           !months.contains(where: { $0.date == thisMonth }) {
            months.insert(MonthTotal(date: thisMonth, days: []), at: 0)
        }
        return months
    }

    private func payment(for month: MonthTotal) -> MonthPayment? {
        payments.first { $0.job?.id == job.id && $0.monthStart == month.date }
    }

    var body: some View {
        Group {
            if jobShifts.isEmpty {
                EmptyState(
                    symbol: job.symbol,
                    title: "No shifts yet",
                    message: "Every month you work at \(job.displayName) shows up here, with a calendar and what it paid.",
                    tint: job.tint
                )
            } else {
                list
            }
        }
        .navigationTitle("All shifts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        .sheet(item: $payTarget) { month in
            MarkPaidSheet(
                job: job,
                monthStart: month.date,
                expected: month.pay,
                existing: payment(for: month)
            )
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
        .tint(job.tint)
        .onAppear(perform: seedExpansion)
    }

    /// Open the most recent month the first time in, so the screen isn't a wall
    /// of closed rows.
    private func seedExpansion() {
        guard !didSeedExpansion, let newest = months.first else { return }
        didSeedExpansion = true
        expandedMonths.insert(newest.date)
    }

    // MARK: - List

    /// A card per month rather than a grouped list of disclosure rows. The
    /// stock ones gave every month the same chevron and the same grey, so the
    /// month you are actually reading looked like the eleven you aren't.
    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(months) { month in
                    monthCard(month)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
    }

    /// One shift on the day → edit it; none → log one there. A day with
    /// several shifts opens in the list instead, so you pick which.
    private func selectDay(_ day: Date, in month: MonthTotal) {
        let shifts = month.days.first { $0.date == day }?.shifts ?? []
        if let target = ShiftEditorTarget.forDay(day, job: job, shifts: shifts) {
            editorTarget = target
        } else {
            withAnimation(.snappy) { _ = expandedDays.insert(day) }
        }
    }

    private func monthCard(_ month: MonthTotal) -> some View {
        let isOpen = expandedMonths.contains(month.date)

        return VStack(spacing: 0) {
            Button {
                withAnimation(.snappy) {
                    if isOpen { expandedMonths.remove(month.date) } else { expandedMonths.insert(month.date) }
                }
            } label: {
                monthHeader(month, isOpen: isOpen)
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(spacing: 14) {
                    Divider()

                    MonthHeatmap(month: month, job: job, openDays: expandedDays) { day in
                        selectDay(day, in: month)
                    }

                    if !month.days.isEmpty {
                        factsRow(month)
                        paymentControl(month)
                        daysList(month)
                    } else {
                        Text("Nothing logged yet. Tap a day to add a shift.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .washedSurface(job.tint)
    }

    // MARK: - Rows

    private func monthHeader(_ month: MonthTotal, isOpen: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.monthTitle(month.date))
                    .font(.system(.headline, design: .rounded).weight(.bold))
                Text(month.days.isEmpty
                     ? "Nothing logged"
                     : "\(Fmt.count(month.dayCount, "day")) · \(Fmt.count(month.shiftCount, "shift"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.money(month.pay))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.money)
                Text(Fmt.hours(month.hours))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(job.tint)
                .rotationEffect(.degrees(isOpen ? 0 : -90))
                .frame(width: 20)
        }
        .padding(16)
        .contentShape(Rectangle())
    }

    /// The month's breakdown as three columns, not three rows of a settings
    /// table. Hours and the total are already on the header.
    private func factsRow(_ month: MonthTotal) -> some View {
        HStack(spacing: 0) {
            if job.tracksTips {
                fact("Base pay", Fmt.money(month.basePay))
                fact("Tips", Fmt.money(month.tips))
            }
            fact("Avg per day", Fmt.hours(month.averageHoursPerDay))
            if !job.tracksTips {
                fact("Shifts", "\(month.shiftCount)")
            }
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Whether this month has been paid, as one control.
    ///
    /// It used to be a line of text in the middle of a stat table, which is
    /// how you end up tapping it by accident and never on purpose. Unpaid it
    /// is a filled button carrying the amount it will propose; paid it is a
    /// status strip you can tap to correct.
    @ViewBuilder
    private func paymentControl(_ month: MonthTotal) -> some View {
        if let payment = payment(for: month) {
            let delta = payment.difference(from: month.pay)
            let matches = abs(delta) < 0.01
            let tint = matches ? Palette.money : (delta < 0 ? Palette.attention : Palette.money)

            Button {
                payTarget = month
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: matches ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(tint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Paid \(Fmt.money(payment.amount))")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        Text(matches
                             ? "On \(Fmt.dayInMonth(payment.paidOn)) · matches this month"
                             : "\(delta < 0 ? "Short" : "Over") by \(Fmt.money(abs(delta))) against \(Fmt.money(month.pay))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "pencil")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tint.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !payment.note.isEmpty {
                Text(payment.note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Button {
                payTarget = month
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Mark as paid")
                    Spacer(minLength: 8)
                    Text(Fmt.money(month.pay))
                        .monospacedDigit()
                        .opacity(0.9)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(colors: [job.tint, job.gradientEnd],
                                   startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        NavigationLink(value: JobRoute.timesheet(month.date)) {
            HStack(spacing: 8) {
                Image(systemName: "tablecells")
                Text("Timesheet")
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(job.tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(job.tint.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Every day worked that month. One shift on a day opens straight into the
    /// editor; several open here so you can pick.
    private func daysList(_ month: MonthTotal) -> some View {
        VStack(spacing: 0) {
            Divider()
            ForEach(month.days) { day in
                let isOpen = expandedDays.contains(day.date)

                Button {
                    if day.shifts.count == 1 {
                        editorTarget = .edit(day.shifts[0], job)
                    } else {
                        withAnimation(.snappy) {
                            if isOpen { expandedDays.remove(day.date) } else { expandedDays.insert(day.date) }
                        }
                    }
                } label: {
                    dayLabel(day, isOpen: isOpen)
                }
                .buttonStyle(.plain)

                if isOpen {
                    ForEach(day.shifts) { shift in
                        Button {
                            editorTarget = .edit(shift, job)
                        } label: {
                            ShiftDetailRow(shift: shift, job: job)
                                .padding(.leading, 12)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                pendingDelete = shift
                            }
                        }
                    }
                }

                if day.id != month.days.last?.id { Divider() }
            }
        }
    }

    private func dayLabel(_ day: DayTotal, isOpen: Bool) -> some View {
        HStack(spacing: 12) {
            DateBadge(date: day.date, tint: job.tint)

            // The badge already says which day it is, so the line beside it
            // says what happened on it.
            VStack(alignment: .leading, spacing: 2) {
                Text(headline(for: day))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                Text(caption(for: day))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(Fmt.hours(day.hours))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(job.tint)

            Image(systemName: day.shifts.count == 1 ? "chevron.right" : "chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(day.shifts.count == 1 || isOpen ? 0 : -90))
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func headline(for day: DayTotal) -> String {
        guard let first = day.shifts.first else { return Fmt.dayHeader(day.date) }
        if day.shifts.count > 1 { return Fmt.count(day.shifts.count, "shift") }
        return "\(Fmt.time(first.checkIn)) → \(Fmt.time(first.checkOut))"
    }

    private func caption(for day: DayTotal) -> String {
        var parts = [Fmt.money(day.pay)]
        if job.tracksTips && day.tips > 0 {
            parts.append("\(Fmt.money(day.tips)) tips")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Expansion state

    private func expansion(for month: MonthTotal) -> Binding<Bool> {
        Binding(
            get: { expandedMonths.contains(month.date) },
            set: { isOpen in
                if isOpen { expandedMonths.insert(month.date) } else { expandedMonths.remove(month.date) }
            }
        )
    }

    private func expansion(for day: DayTotal) -> Binding<Bool> {
        Binding(
            get: { expandedDays.contains(day.date) },
            set: { isOpen in
                if isOpen { expandedDays.insert(day.date) } else { expandedDays.remove(day.date) }
            }
        )
    }
}

/// One job's month as a plain table: each day worked, from when to when, and
/// the total underneath — something to show or screenshot.
struct TimesheetView: View {
    let job: Job
    let month: Date

    @Query(sort: \Shift.checkIn) private var shifts: [Shift]

    private var monthShifts: [Shift] {
        shifts.logged.filter { $0.job?.id == job.id && Calendar.current.isDate($0.checkIn, equalTo: month, toGranularity: .month) }
    }

    private var totalHours: Double { monthShifts.reduce(0) { $0 + $1.hours } }

    @State private var exported: TimesheetExport.File?
    @State private var exportFailed = false

    var body: some View {
        List {
            Section {
                if monthShifts.isEmpty {
                    Text("Nothing logged at \(job.displayName) in \(Fmt.monthTitle(month)).")
                        .foregroundStyle(.secondary)
                } else {
                    table
                }
            } header: {
                SectionHeader("\(job.displayName) · \(Fmt.monthTitle(month))")
            }
            .listRowBackground(TintedRow(colour: job.tint))
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Timesheet")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { export(.pdf) } label: {
                        Label("PDF — to print or send", systemImage: "doc.richtext")
                    }
                    Button { export(.csv) } label: {
                        Label("CSV — for a spreadsheet", systemImage: "tablecells")
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(monthShifts.isEmpty)
            }
        }
        .sheet(item: $exported) { file in
            ShareSheet(url: file.url)
        }
        .alert("Couldn't make the file", isPresented: $exportFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Something went wrong writing the timesheet out. If your phone is low on storage, freeing some space should fix it.")
        }
        .tint(job.tint)
    }

    private func export(_ format: TimesheetExport.Format) {
        if let file = TimesheetExport.make(format, job: job, month: month, shifts: monthShifts) {
            exported = file
        } else {
            exportFailed = true
        }
    }

    private var table: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text("Date")
                Text("From")
                Text("To")
                Text("Hours").gridColumnAlignment(.trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            Divider()

            ForEach(monthShifts) { shift in
                GridRow {
                    Text(Fmt.dayInMonth(shift.checkIn))
                    Text(Fmt.time(shift.checkIn))
                    Text(Fmt.time(shift.checkOut) + (shift.isOvernight ? "⁺¹" : ""))
                    Text(Fmt.hours(shift.hours))
                        .foregroundStyle(job.tint)
                }
                .font(.subheadline)
                .monospacedDigit()
            }

            Divider()

            GridRow {
                Text("Total")
                    .gridCellColumns(3)
                Text(Fmt.hours(totalHours))
                    .foregroundStyle(job.tint)
            }
            .font(.headline)
            .monospacedDigit()

            GridRow {
                Text("\(Fmt.count(Set(monthShifts.map(\.day)).count, "day")) · \(Fmt.count(monthShifts.count, "shift"))")
                    .gridCellColumns(4)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

/// One shift, fully spelled out: when you checked in and out, and what it paid.
struct ShiftDetailRow: View {
    let shift: Shift
    let job: Job

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("\(Fmt.time(shift.checkIn)) → \(Fmt.time(shift.checkOut))")
                    .font(.subheadline.weight(.semibold))
                if shift.isOvernight {
                    Text("+1")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }

                Spacer(minLength: 8)

                Text(Fmt.hours(shift.hours))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(job.tint)
            }

            VStack(spacing: 6) {
                detail("Checked in", Fmt.time(shift.checkIn))
                detail("Checked out", shift.isOvernight
                       ? "\(Fmt.time(shift.checkOut)) (next day)"
                       : Fmt.time(shift.checkOut))
                detail("Base pay", "\(Fmt.money(shift.basePay)) · \(Fmt.money(shift.hourlyRate))/h")
                if job.tracksTips {
                    detail("Tips", shift.tipsAmount > 0 ? Fmt.money(shift.tipsAmount) : "—")
                    detail("Total", Fmt.money(shift.totalPay))
                }
                if !shift.note.isEmpty {
                    detail("Note", shift.note)
                }
            }

            Text("Tap to edit")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    NavigationStack {
        AllShiftsView(job: Job(name: "M🐱ček", color: .orange, symbol: "fork.knife", hourlyRate: 9, tracksTips: true))
    }
    .modelContainer(PreviewData.container)
}
