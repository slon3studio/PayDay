import SwiftUI
import SwiftData

enum ShiftEditorTarget: Identifiable {
    case new(Job)
    /// A new shift on a day picked from a calendar, at the job's usual times.
    case newOn(Job, Date)
    /// The job comes along so the editor never has to guess it from the shift.
    case edit(Shift, Job)

    var id: String {
        switch self {
        case .new(let job): return "new-\(job.id.uuidString)"
        case .newOn(let job, let day): return "new-\(job.id.uuidString)-\(day.timeIntervalSince1970)"
        case .edit(let shift, _): return "edit-\(shift.id.uuidString)"
        }
    }

    var job: Job {
        switch self {
        case .new(let job), .newOn(let job, _), .edit(_, let job): return job
        }
    }

    var existing: Shift? {
        if case .edit(let shift, _) = self { return shift }
        return nil
    }

    /// What tapping a day on a calendar should open: that day's shift to edit,
    /// or a fresh one on that day. `nil` when the day has several shifts and
    /// there's no single one to pick.
    static func forDay(_ day: Date, job: Job, shifts: [Shift]) -> ShiftEditorTarget? {
        switch shifts.count {
        case 0: return .newOn(job, day)
        case 1: return .edit(shifts[0], job)
        default: return nil
        }
    }
}

/// Log a new shift or edit an existing one. The date field is the day you
/// checked in; a check-out earlier in the day rolls over to the next morning.
struct ShiftEditorView: View {
    let target: ShiftEditorTarget

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var day: Date
    @State private var checkInTime: Date
    @State private var checkOutTime: Date
    @State private var tipsText: String
    @State private var note: String
    @State private var breakMinutes: Int
    @State private var isPlanned: Bool
    @State private var confirmingDelete = false
    @State private var dateFieldToken = UUID()

    private var job: Job { target.job }

    init(target: ShiftEditorTarget) {
        self.target = target
        let calendar = Calendar.current

        if let shift = target.existing {
            _day = State(initialValue: calendar.startOfDay(for: shift.checkIn))
            _checkInTime = State(initialValue: shift.checkIn)
            _checkOutTime = State(initialValue: shift.checkOut)
            _tipsText = State(initialValue: shift.tipsAmount > 0 ? String(format: "%.2f", shift.tipsAmount) : "")
            _note = State(initialValue: shift.note)
            _breakMinutes = State(initialValue: shift.breakMinutes)
            _isPlanned = State(initialValue: shift.isPlanned)
        } else {
            var now = Date()
            if case .newOn(_, let picked) = target { now = picked }
            let checkIn = target.job.defaultCheckIn
            let checkOut = target.job.defaultCheckOut
            let start = calendar.date(bySettingHour: checkIn.hour, minute: checkIn.minute, second: 0, of: now) ?? now
            let end = calendar.date(bySettingHour: checkOut.hour, minute: checkOut.minute, second: 0, of: now) ?? now
            _day = State(initialValue: calendar.startOfDay(for: now))
            _checkInTime = State(initialValue: start)
            _checkOutTime = State(initialValue: end)
            _tipsText = State(initialValue: "")
            _note = State(initialValue: "")
            _breakMinutes = State(initialValue: target.job.tracksBreaks ? target.job.defaultBreakMinutes : 0)
            // A day that hasn't happened yet can only be a plan.
            _isPlanned = State(initialValue: Calendar.current.startOfDay(for: now) > Calendar.current.startOfDay(for: .now))
        }
    }

    // MARK: - Computed times

    private var resolvedCheckIn: Date {
        Self.combine(day: day, time: checkInTime)
    }

    private var resolvedCheckOut: Date {
        let sameDay = Self.combine(day: day, time: checkOutTime)
        guard sameDay <= resolvedCheckIn else { return sameDay }
        // Check-out at or before check-in means the shift ran past midnight.
        return Calendar.current.date(byAdding: .day, value: 1, to: sameDay) ?? sameDay
    }

    /// The span between the two pickers, break included.
    private var span: Double {
        max(0, resolvedCheckOut.timeIntervalSince(resolvedCheckIn)) / 3600
    }

    /// What the shift actually counts for, and what it's paid on.
    private var duration: Double {
        max(0, span - Double(breakMinutes) / 60)
    }

    private var isOvernight: Bool {
        !Calendar.current.isDate(resolvedCheckIn, inSameDayAs: resolvedCheckOut)
    }

    private var tipsValue: Double {
        Double(tipsText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var canSave: Bool { duration > 0 }

    /// An existing shift keeps the rate it was logged at.
    private var rate: Double { target.existing?.hourlyRate ?? job.hourlyRate }

    /// The stock date field, which keeps its calendar up after you've picked a
    /// day. Giving it a fresh `id` on selection tears the picker down and
    /// rebuilds it, taking the calendar with it — the row itself is unchanged.
    private var dateRow: some View {
        DatePicker("Date", selection: $day, displayedComponents: .date)
            .id(dateFieldToken)
            .onChange(of: day) { dateFieldToken = UUID() }
    }

    private var navigationTitle: String {
        switch target {
        case .edit: return "Edit shift"
        case .new, .newOn: return isPlanned ? "Plan \(job.displayName) shift" : "Log \(job.displayName) shift"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    summary
                    timesCard
                    if job.tracksTips { tipsCard }
                    if job.tracksBreaks { breakCard }
                    noteCard
                    if let shift = target.existing { deleteButton(shift) }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isPlanned ? "Plan" : "Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
        .tint(job.tint)
        .appAppearance()
    }


    // MARK: - Cards

    /// Date and both times in one block, with the times as the big values
    /// they are rather than two rows that look like settings.
    private var timesCard: some View {
        VStack(spacing: 0) {
            Picker("", selection: $isPlanned.animation(.snappy)) {
                Text("Worked").tag(false)
                Text("Planned").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 4)

            HStack(spacing: 0) {
                timeBlock("Starts", selection: $checkInTime)
                Rectangle()
                    .fill(Color(.separator).opacity(0.5))
                    .frame(width: 1, height: 46)
                timeBlock("Ends", selection: $checkOutTime, badge: isOvernight ? "+1" : nil)
            }
            .padding(.vertical, 14)

            Divider().padding(.leading, 16)

            HStack {
                Label("Date", systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                dateRow
                    .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if isOvernight {
                Divider().padding(.leading, 16)
                Label("Ends the next morning — counted on \(Fmt.dayHeader(Calendar.current.startOfDay(for: resolvedCheckIn))).",
                      systemImage: "moon.stars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous))
    }

    private func timeBlock(_ label: String, selection: Binding<Date>, badge: String? = nil) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Text(label.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(job.tint.opacity(0.18), in: Capsule())
                        .foregroundStyle(job.tint)
                }
            }
            DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
        .frame(maxWidth: .infinity)
    }

    private var tipsCard: some View {
        HStack {
            Label("Tips earned", systemImage: "banknote")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            TextField("0", text: $tipsText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .font(.title3.weight(.semibold))
                .frame(maxWidth: 130)
            Text("€")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous))
    }

    private var breakCard: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Unpaid break", systemImage: "cup.and.saucer")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $breakMinutes.animation(.snappy)) {
                    Text("None").tag(0)
                    ForEach([15, 20, 30, 45, 60], id: \.self) { Text("\($0) min").tag($0) }
                }
                .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if breakMinutes > 0 {
                Divider().padding(.leading, 16)
                HStack(spacing: 0) {
                    breakStat("On the clock", Fmt.hours(span), .secondary)
                    breakStat("Break", "−\(breakMinutes)m", .secondary)
                    breakStat("Counts as", Fmt.hours(duration), job.tint)
                }
                .padding(.vertical, 12)
            }
        }
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous))
    }

    private func breakStat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOTE")
                .font(.caption2.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            TextField("Anything worth remembering", text: $note, axis: .vertical)
                .lineLimit(1...4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous))
    }

    private func deleteButton(_ shift: Shift) -> some View {
        Button(role: .destructive) {
            confirmingDelete = true
        } label: {
            Label("Delete shift", systemImage: "trash")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous))
        // An alert rather than a confirmation dialog, which iOS 26 shows as a
        // popover pinned to the button.
        .alert("Delete this shift?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { delete(shift) }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("\(Fmt.dayHeader(shift.day)) · \(Fmt.time(shift.checkIn))–\(Fmt.time(shift.checkOut))")
        }
    }

    // MARK: - Summary

    /// The shift as it currently stands.
    ///
    /// Deliberately not the job tab's card. That one is a full gradient
    /// because it's the first thing you see and it owns the screen; copying it
    /// here would make the sheet read as the same card twice. This is a plain
    /// surface with the job's colour as a rail down the side — related, not
    /// identical — and it follows the app's rule: money green, hours in the
    /// job's colour.
    private var summary: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [job.tint, job.gradientEnd],
                           startPoint: .top, endPoint: .bottom)
                .frame(width: 6)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text(Fmt.dayHeader(Calendar.current.startOfDay(for: resolvedCheckIn)).uppercased())
                        .font(.caption2.weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                    if isPlanned {
                        Text("PLANNED")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(0.6)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(job.tint.opacity(0.16), in: Capsule())
                            .foregroundStyle(job.tint)
                    }
                    Spacer()
                    Image(systemName: job.symbol)
                        .font(.footnote)
                        .foregroundStyle(job.tint)
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Fmt.money(duration * rate + (job.tracksTips ? tipsValue : 0)))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isPlanned ? Color.secondary : Palette.money)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text(Fmt.hours(duration))
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(job.tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(job.tint.opacity(0.14), in: Capsule())
                }

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous))
        .animation(.snappy, value: duration)
    }

    /// "17:00 → 23:30 · 11,40 €/h · 30m break"
    private var detail: String {
        var parts = ["\(Fmt.time(resolvedCheckIn)) → \(Fmt.time(resolvedCheckOut))\(isOvernight ? " +1" : "")"]
        parts.append("\(Fmt.money(rate))/h")
        if breakMinutes > 0 { parts.append("\(breakMinutes)m break") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Saving

    private func save() {
        let tips = job.tracksTips ? tipsValue : nil

        // A job that doesn't deduct breaks can't leave one behind on a shift.
        let unpaidBreak = job.tracksBreaks ? breakMinutes : 0

        if let shift = target.existing {
            shift.checkIn = resolvedCheckIn
            shift.checkOut = resolvedCheckOut
            shift.tips = tips
            shift.breakMinutes = unpaidBreak
            shift.isPlanned = isPlanned
            shift.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let shift = Shift(
                job: job,
                checkIn: resolvedCheckIn,
                checkOut: resolvedCheckOut,
                tips: tips,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                breakMinutes: unpaidBreak,
                isPlanned: isPlanned
            )
            context.insert(shift)
        }
        Haptics.success()
        dismiss()
    }

    /// Closes the sheet first and deletes once it's gone — deleting while it's
    /// still up leaves the editor re-reading a shift that no longer exists.
    private func delete(_ shift: Shift) {
        let context = context
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            context.delete(shift)
        }
    }

    /// Take the day from `day` and the hour/minute from `time`.
    private static func combine(day: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let dayParts = calendar.dateComponents([.year, .month, .day], from: day)
        let timeParts = calendar.dateComponents([.hour, .minute], from: time)
        var parts = DateComponents()
        parts.year = dayParts.year
        parts.month = dayParts.month
        parts.day = dayParts.day
        parts.hour = timeParts.hour
        parts.minute = timeParts.minute
        return calendar.date(from: parts) ?? day
    }
}

#Preview {
    ShiftEditorView(target: .new(Job(name: "M🐱ček", color: .orange, symbol: "fork.knife", hourlyRate: 9, tracksTips: true)))
        .modelContainer(PreviewData.container)
}
