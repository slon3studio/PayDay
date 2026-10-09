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
        case .new, .newOn: return "Log \(job.displayName) shift"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    dateRow
                    DatePicker("Check in", selection: $checkInTime, displayedComponents: .hourAndMinute)
                    DatePicker("Check out", selection: $checkOutTime, displayedComponents: .hourAndMinute)
                } footer: {
                    if isOvernight {
                        Label("Ends the next morning — counted on \(Fmt.dayHeader(Calendar.current.startOfDay(for: resolvedCheckIn))).",
                              systemImage: "moon.stars")
                    }
                }

                if job.tracksTips {
                    Section("Tips") {
                        HStack {
                            Text("Tips earned")
                            Spacer()
                            TextField("0.00", text: $tipsText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 120)
                            Text("€").foregroundStyle(.secondary)
                        }
                    }
                }

                if job.tracksBreaks {
                    Section {
                        Picker("Unpaid break", selection: $breakMinutes) {
                            Text("None").tag(0)
                            ForEach([15, 20, 30, 45, 60], id: \.self) { minutes in
                                Text("\(minutes) min").tag(minutes)
                            }
                        }
                    } footer: {
                        Text("Comes off the hours this shift counts for.")
                    }
                }

                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section {
                    if breakMinutes > 0 {
                        StatRow(label: "On the clock", value: Fmt.hours(span))
                        StatRow(label: "Break", value: "−\(breakMinutes) min")
                    }
                    StatRow(label: "Hours", value: Fmt.hours(duration), emphasized: true, tint: job.tint)
                    StatRow(label: "Base pay", value: Fmt.money(duration * rate))
                    if job.tracksTips {
                        StatRow(label: "Total incl. tips", value: Fmt.money(duration * rate + tipsValue), emphasized: true, tint: .green)
                    }
                } header: {
                    Text("This shift")
                } footer: {
                    Text("\(job.displayName) pays \(Fmt.money(rate)) per hour.")
                }

                if let shift = target.existing {
                    Section {
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Label("Delete shift", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        // An alert rather than a confirmation dialog, which
                        // iOS 26 shows as a popover pinned to the button.
                        .alert("Delete this shift?", isPresented: $confirmingDelete) {
                            Button("Delete", role: .destructive) { delete(shift) }
                            Button("Keep", role: .cancel) {}
                        } message: {
                            Text("\(Fmt.dayHeader(shift.day)) · \(Fmt.time(shift.checkIn))–\(Fmt.time(shift.checkOut))")
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
        .tint(job.tint)
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
            shift.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let shift = Shift(
                job: job,
                checkIn: resolvedCheckIn,
                checkOut: resolvedCheckOut,
                tips: tips,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                breakMinutes: unpaidBreak
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
