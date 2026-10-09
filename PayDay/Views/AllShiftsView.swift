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

    private var list: some View {
        List {
            ForEach(months) { month in
                Section {
                    DisclosureGroup(isExpanded: expansion(for: month)) {
                        MonthHeatmap(month: month, job: job, openDays: expandedDays) { day in
                            selectDay(day, in: month)
                        }

                        if !month.days.isEmpty {
                            monthFacts(month)

                            NavigationLink {
                                TimesheetView(job: job, month: month.date)
                            } label: {
                                Label("Timesheet", systemImage: "tablecells")
                                    .foregroundStyle(job.tint)
                            }
                        }

                        ForEach(month.days) { day in
                            DisclosureGroup(isExpanded: expansion(for: day)) {
                                ForEach(day.shifts) { shift in
                                    Button {
                                        editorTarget = .edit(shift, job)
                                    } label: {
                                        ShiftDetailRow(shift: shift, job: job)
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
                            } label: {
                                dayLabel(day)
                            }
                        }
                    } label: {
                        monthLabel(month)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
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

    // MARK: - Rows

    private func monthLabel(_ month: MonthTotal) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.monthTitle(month.date))
                    .font(.headline)
                Text("\(Fmt.count(month.dayCount, "day")) · \(Fmt.count(month.shiftCount, "shift"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.hours(month.hours))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(job.tint)
                Text(Fmt.money(month.pay))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    /// The month's breakdown, shown once it's open. Hours and the total are
    /// already on the month's own row.
    private func monthFacts(_ month: MonthTotal) -> some View {
        VStack(spacing: 8) {
            if job.tracksTips {
                StatRow(label: "Base pay", value: Fmt.money(month.basePay))
                StatRow(label: "Tips", value: Fmt.money(month.tips))
            }
            StatRow(label: "Avg per day", value: Fmt.hours(month.averageHoursPerDay))

            Divider()
            paidRow(month)
        }
        .padding(.vertical, 4)
    }

    /// What actually arrived for this month, against what it should have been.
    @ViewBuilder
    private func paidRow(_ month: MonthTotal) -> some View {
        if let payment = payment(for: month) {
            let delta = payment.difference(from: month.pay)
            let matches = abs(delta) < 0.01

            Button {
                payTarget = month
            } label: {
                VStack(spacing: 6) {
                    StatRow(label: "Paid \(Fmt.dayInMonth(payment.paidOn))",
                            value: Fmt.money(payment.amount),
                            emphasized: true,
                            tint: matches ? Palette.money : (delta < 0 ? Palette.attention : Palette.money))
                    HStack(spacing: 4) {
                        Image(systemName: matches ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(matches ? Palette.money : Palette.attention)
                        Text(matches
                             ? "Matches what this month should have paid."
                             : "\(delta < 0 ? "Short" : "Over") by \(Fmt.money(abs(delta))) against \(Fmt.money(month.pay)).")
                        Spacer(minLength: 0)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                    if !payment.note.isEmpty {
                        HStack {
                            Text(payment.note)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Button {
                payTarget = month
            } label: {
                Label("Mark as paid", systemImage: "checkmark.circle")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(job.tint)
        }
    }

    private func dayLabel(_ day: DayTotal) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.dayInMonth(day.date))
                    .font(.body.weight(.medium))
                Text(caption(for: day))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(Fmt.hours(day.hours))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(job.tint)
        }
        .contentShape(Rectangle())
    }

    private func caption(for day: DayTotal) -> String {
        var parts = [Fmt.money(day.pay)]
        if day.shifts.count > 1 {
            parts.append(Fmt.count(day.shifts.count, "shift"))
        }
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
        shifts.filter { $0.job?.id == job.id && Calendar.current.isDate($0.checkIn, equalTo: month, toGranularity: .month) }
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
