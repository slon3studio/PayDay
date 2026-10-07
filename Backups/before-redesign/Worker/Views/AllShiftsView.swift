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
        allShifts.filter { $0.job == job }
    }

    private var months: [MonthTotal] {
        StatsEngine.months(from: jobShifts)
    }

    private var stats: ShiftStats {
        ShiftStats(job: job, shifts: jobShifts)
    }

    private func payment(for month: MonthTotal) -> MonthPayment? {
        payments.first { $0.job == job && $0.monthStart == month.date }
    }

    var body: some View {
        Group {
            if months.isEmpty {
                ContentUnavailableView(
                    "No shifts yet",
                    systemImage: job.symbol,
                    description: Text("Log a shift for \(job.displayName) and it will show up here.")
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
            Section {
                totalsGrid
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            } header: {
                Text("All time")
            }

            ForEach(months) { month in
                Section {
                    DisclosureGroup(isExpanded: expansion(for: month)) {
                        MonthHeatmap(month: month, job: job, openDays: expandedDays) { day in
                            withAnimation(.snappy) {
                                if expandedDays.contains(day) {
                                    expandedDays.remove(day)
                                } else {
                                    expandedDays.insert(day)
                                }
                            }
                        }

                        monthFacts(month)

                        ForEach(month.days) { day in
                            DisclosureGroup(isExpanded: expansion(for: day)) {
                                ForEach(day.shifts) { shift in
                                    Button {
                                        editorTarget = .edit(shift)
                                    } label: {
                                        ShiftDetailRow(shift: shift)
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

    private var totalsGrid: some View {
        StatGrid {
            StatTile(
                title: "Total hours",
                value: Fmt.hours(stats.totalHours),
                caption: "\(Fmt.count(stats.dayCount, "day")) · \(Fmt.count(stats.shiftCount, "shift"))",
                tint: job.tint
            )
            StatTile(
                title: job.tracksTips ? "Earned (incl. tips)" : "Earned",
                value: Fmt.money(stats.totalEarnings),
                caption: "at \(Fmt.money(job.hourlyRate))/h",
                tint: .green
            )
            StatTile(
                title: "Avg per day",
                value: Fmt.hours(stats.averageHoursPerDay),
                caption: "Across \(Fmt.count(months.count, "month"))"
            )
            if job.tracksTips {
                StatTile(
                    title: "Tips",
                    value: Fmt.money(stats.totalTips),
                    caption: "Avg \(Fmt.money(stats.averageTipsPerShift))/shift"
                )
            } else if let longest = stats.longestDay {
                StatTile(
                    title: "Longest day",
                    value: Fmt.hours(longest.hours),
                    caption: Fmt.dayHeader(longest.date)
                )
            }
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

    /// The month's numbers, shown once it's open.
    private func monthFacts(_ month: MonthTotal) -> some View {
        VStack(spacing: 8) {
            StatRow(label: "Hours", value: Fmt.hours(month.hours), emphasized: true, tint: job.tint)
            StatRow(label: "Base pay", value: Fmt.money(month.basePay))
            if job.tracksTips {
                StatRow(label: "Tips", value: Fmt.money(month.tips))
            }
            StatRow(label: "Total earned", value: Fmt.money(month.pay), emphasized: true, tint: .green)
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
                            tint: matches ? .green : (delta < 0 ? .orange : .green))
                    HStack(spacing: 4) {
                        Image(systemName: matches ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(matches ? .green : .orange)
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

/// One shift, fully spelled out: when you checked in and out, and what it paid.
struct ShiftDetailRow: View {
    let shift: Shift

    private var job: Job { shift.job }

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
                detail("Base pay", "\(Fmt.money(shift.basePay)) · \(Fmt.money(job.hourlyRate))/h")
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
        AllShiftsView(job: .macek)
    }
    .modelContainer(PreviewData.container)
}
