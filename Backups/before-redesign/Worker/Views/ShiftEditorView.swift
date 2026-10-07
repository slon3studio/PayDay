import SwiftUI
import SwiftData

enum ShiftEditorTarget: Identifiable {
    case new(Job)
    case edit(Shift)
    /// Just clocked out — the times are real, but you still get to adjust them
    /// before they're saved.
    case clockedOut(Job, checkIn: Date, checkOut: Date)

    var id: String {
        switch self {
        case .new(let job): return "new-\(job.rawValue)"
        case .edit(let shift): return "edit-\(shift.id.uuidString)"
        case .clockedOut(let job, let checkIn, _): return "clock-\(job.rawValue)-\(checkIn.timeIntervalSince1970)"
        }
    }

    var job: Job {
        switch self {
        case .new(let job): return job
        case .edit(let shift): return shift.job
        case .clockedOut(let job, _, _): return job
        }
    }

    var existing: Shift? {
        if case .edit(let shift) = self { return shift }
        return nil
    }

    /// Times to open with, when they're already known.
    var prefilled: (checkIn: Date, checkOut: Date)? {
        if case .clockedOut(_, let checkIn, let checkOut) = self { return (checkIn, checkOut) }
        return nil
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
        } else if let times = target.prefilled {
            _day = State(initialValue: calendar.startOfDay(for: times.checkIn))
            _checkInTime = State(initialValue: times.checkIn)
            _checkOutTime = State(initialValue: times.checkOut)
            _tipsText = State(initialValue: "")
            _note = State(initialValue: "")
        } else {
            let now = Date()
            let checkIn = target.job.defaultCheckIn
            let checkOut = target.job.defaultCheckOut
            let start = calendar.date(bySettingHour: checkIn.hour, minute: checkIn.minute, second: 0, of: now) ?? now
            let end = calendar.date(bySettingHour: checkOut.hour, minute: checkOut.minute, second: 0, of: now) ?? now
            _day = State(initialValue: calendar.startOfDay(for: now))
            _checkInTime = State(initialValue: start)
            _checkOutTime = State(initialValue: end)
            _tipsText = State(initialValue: "")
            _note = State(initialValue: "")
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

    private var duration: Double {
        max(0, resolvedCheckOut.timeIntervalSince(resolvedCheckIn)) / 3600
    }

    private var isOvernight: Bool {
        !Calendar.current.isDate(resolvedCheckIn, inSameDayAs: resolvedCheckOut)
    }

    private var tipsValue: Double {
        Double(tipsText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var canSave: Bool { duration > 0 }

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
        case .clockedOut: return "Clocked out"
        case .new: return "Log \(job.displayName) shift"
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

                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section {
                    StatRow(label: "Hours", value: Fmt.hours(duration), emphasized: true, tint: job.tint)
                    StatRow(label: "Base pay", value: Fmt.money(duration * job.hourlyRate))
                    if job.tracksTips {
                        StatRow(label: "Total incl. tips", value: Fmt.money(duration * job.hourlyRate + tipsValue), emphasized: true, tint: .green)
                    }
                } header: {
                    Text("This shift")
                } footer: {
                    Text("\(job.displayName) pays \(Fmt.money(job.hourlyRate)) per hour.")
                }

                if target.existing != nil {
                    Section {
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Label("Delete shift", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissesKeyboardOnTap()
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
            .confirmationDialog("Delete this shift?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let shift = target.existing {
                        context.delete(shift)
                    }
                    dismiss()
                }
                Button("Keep", role: .cancel) {}
            }
        }
        .tint(job.tint)
    }

    // MARK: - Saving

    private func save() {
        let tips = job.tracksTips ? tipsValue : nil

        if let shift = target.existing {
            shift.checkIn = resolvedCheckIn
            shift.checkOut = resolvedCheckOut
            shift.tips = tips
            shift.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let shift = Shift(
                job: job,
                checkIn: resolvedCheckIn,
                checkOut: resolvedCheckOut,
                tips: tips,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            context.insert(shift)
        }
        dismiss()
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
    ShiftEditorView(target: .new(.macek))
        .modelContainer(PreviewData.container)
}
