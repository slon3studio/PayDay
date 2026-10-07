import SwiftUI
import SwiftData

/// One tab per job: clock in, log a shift, see the stats, browse the history.
struct JobView: View {
    let job: Job

    @Environment(\.modelContext) private var context
    @Query(sort: \Shift.checkIn, order: .reverse) private var allShifts: [Shift]

    @State private var scope: StatsScope = .month
    @State private var editorTarget: ShiftEditorTarget?
    @State private var pendingDelete: Shift?

    /// Remembered per job — a weekday desk job and a weekend waiting job want
    /// different projection bases.
    @AppStorage private var basisRaw: String

    init(job: Job) {
        self.job = job
        let fallback: ProjectionBasis = job.worksWeekends ? .pattern : .weekdays
        _basisRaw = AppStorage(wrappedValue: fallback.rawValue, "projectionBasis.\(job.rawValue)")
    }

    private var basis: Binding<ProjectionBasis> {
        Binding(
            get: { ProjectionBasis(rawValue: basisRaw) ?? .weekdays },
            set: { basisRaw = $0.rawValue }
        )
    }

    // MARK: - Derived data

    private var jobShifts: [Shift] {
        allShifts.filter { $0.job == job }
    }

    private var scopedStats: ShiftStats {
        ShiftStats(job: job, shifts: StatsEngine.shifts(jobShifts, in: scope))
    }

    private var projection: MonthProjection {
        StatsEngine.projection(for: job, allShiftsForJob: jobShifts, basis: basis.wrappedValue)
    }

    private var lastShift: Shift? { jobShifts.first }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(job.displayName)
                .navigationBarTitleDisplayMode(.large)
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
            Section {
                ClockCard(
                    job: job,
                    lastShift: lastShift,
                    onClockOut: { checkIn, checkOut in
                        editorTarget = .clockedOut(job, checkIn: checkIn, checkOut: checkOut)
                    },
                    onRepeat: {
                        if let last = lastShift {
                            withAnimation(.snappy) { repeatLastShift(last) }
                        }
                    }
                )
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
            }

            if jobShifts.isEmpty {
                Section {
                    emptyState
                }
            } else {
                Section {
                    Picker("Scope", selection: $scope.animation(.default)) {
                        ForEach(StatsScope.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)

                    statsGrid
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                }

                Section {
                    ProjectionCard(projection: projection, basis: basis)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Projected pay · \(Fmt.monthTitle(.now))")
                }

                Section {
                    viewAllLink
                }

                shiftSections
            }
        }
        .listStyle(.insetGrouped)
        // Phone-sized: the default gap between sections wastes most of a screen
        // over this many cards.
        .listSectionSpacing(.compact)
        // Don't let a screen that already fits be dragged: scrolling collapses
        // the large title to the small centred one, so a half-empty tab would
        // otherwise look different from a full one.
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
        context.insert(Shift(
            job: job,
            checkIn: checkIn,
            checkOut: checkIn.addingTimeInterval(last.checkOut.timeIntervalSince(last.checkIn))
        ))
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

    private var statsGrid: some View {
        StatGrid {
            StatTile(
                title: "Total hours",
                value: Fmt.hours(scopedStats.totalHours),
                caption: "\(Fmt.count(scopedStats.dayCount, "day")) · \(Fmt.count(scopedStats.shiftCount, "shift"))",
                tint: job.tint
            )
            StatTile(
                title: job.tracksTips ? "Earned (incl. tips)" : "Earned",
                value: Fmt.money(scopedStats.totalEarnings),
                caption: "at \(Fmt.money(job.hourlyRate))/h",
                tint: .green
            )
            StatTile(
                title: "Avg per day",
                value: Fmt.hours(scopedStats.averageHoursPerDay),
                caption: "Avg per shift \(Fmt.hours(scopedStats.averageHoursPerShift))"
            )
            if job.tracksTips {
                StatTile(
                    title: "Tips",
                    value: Fmt.money(scopedStats.totalTips),
                    caption: "Avg \(Fmt.money(scopedStats.averageTipsPerShift))/shift"
                )
            } else if let longest = scopedStats.longestDay {
                StatTile(
                    title: "Longest day",
                    value: Fmt.hours(longest.hours),
                    caption: Fmt.dayHeader(longest.date)
                )
            }
        }
    }

    @ViewBuilder
    private var shiftSections: some View {
        if scopedStats.days.isEmpty {
            Section("Days worked") {
                Text("No shifts logged \(scope == .month ? "this month" : "yet").")
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach(scopedStats.days) { day in
                Section {
                    ForEach(day.shifts) { shift in
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
                } header: {
                    // Just the day. The hours and tips are already on the row
                    // itself, so repeating them here was noise.
                    Text(Fmt.dayHeader(day.date))
                        .font(.footnote.weight(.medium))
                        .textCase(nil)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No shifts yet", systemImage: job.symbol)
        } description: {
            Text("Clock in above, or log a shift by hand, at \(Fmt.money(job.hourlyRate))/h.")
        } actions: {
            Button("Log a shift") { editorTarget = .new(job) }
                .buttonStyle(.borderedProminent)
                .tint(job.tint)
        }
    }
}

/// One shift inside a day section.
struct ShiftRow: View {
    let shift: Shift

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(Fmt.time(shift.checkIn)) → \(Fmt.time(shift.checkOut))")
                        .font(.body.weight(.medium))
                    if shift.isOvernight {
                        Text("+1")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                }
                HStack(spacing: 6) {
                    Text(Fmt.money(shift.basePay))
                    if shift.job.tracksTips, shift.tipsAmount > 0 {
                        Text("+ \(Fmt.money(shift.tipsAmount)) tips")
                    }
                    if !shift.note.isEmpty {
                        Text("· \(shift.note)").lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(Fmt.hours(shift.hours))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(shift.job.tint)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    JobView(job: .macek)
        .modelContainer(PreviewData.container)
}
