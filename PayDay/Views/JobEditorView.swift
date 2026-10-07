import SwiftUI
import SwiftData

enum JobEditorTarget: Identifiable {
    case new
    case edit(Job)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let job): return job.id.uuidString
        }
    }

    var existing: Job? {
        if case .edit(let job) = self { return job }
        return nil
    }
}

/// Add a job or change one: what it's called, how it looks, what it pays, its
/// usual hours and its monthly goal. Nothing is written until Save.
struct JobEditorView: View {
    let target: JobEditorTarget

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var jobs: [Job]
    @Query private var shifts: [Shift]

    /// Shared with `ContentView`, so a new job opens on its own tab.
    @AppStorage("selectedTab") private var selectedTab = ""

    @State private var name: String
    @State private var color: JobColor
    @State private var symbol: String
    @State private var rateText: String
    @State private var tracksTips: Bool
    @State private var worksWeekends: Bool
    @State private var checkIn: Date
    @State private var checkOut: Date
    @State private var goalText: String
    @State private var goalKind: GoalKind
    @State private var confirmingDelete = false

    init(target: JobEditorTarget) {
        self.target = target
        let job = target.existing

        _name = State(initialValue: job?.name ?? "")
        _color = State(initialValue: job?.jobColor ?? .blue)
        _symbol = State(initialValue: job?.symbol ?? JobSymbol.fallback)
        _rateText = State(initialValue: job.map { String(format: "%.2f", $0.hourlyRate) } ?? "")
        _tracksTips = State(initialValue: job?.tracksTips ?? false)
        _worksWeekends = State(initialValue: job?.worksWeekends ?? false)
        // A new job starts out as a plain 8-to-4 day; change it to suit.
        _checkIn = State(initialValue: Self.date(minutes: job?.defaultCheckInMinutes ?? 8 * 60))
        _checkOut = State(initialValue: Self.date(minutes: job?.defaultCheckOutMinutes ?? 16 * 60))
        let goal = job?.goalTarget ?? 0
        _goalText = State(initialValue: goal > 0 ? String(format: "%g", goal) : "")
        _goalKind = State(initialValue: job?.goalKind ?? .money)
    }

    private var rate: Double {
        Double(rateText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var goal: Double {
        Double(goalText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool { !trimmedName.isEmpty && rate > 0 }

    private var shiftCount: Int {
        guard let job = target.existing else { return 0 }
        return shifts.filter { $0.job?.id == job.id }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    preview
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    TextField("e.g. Café, Office, Tutoring", text: $name)
                } header: {
                    Text("Name")
                } footer: {
                    Text("Shown on its tab. Emoji welcome.")
                }

                Section("Colour") {
                    colorGrid
                }

                Section("Icon") {
                    symbolGrid
                }

                Section {
                    HStack {
                        Text("Hourly rate")
                        Spacer()
                        TextField("0.00", text: $rateText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(maxWidth: 90)
                        Text("€/h").foregroundStyle(.secondary)
                    }
                    Toggle("Tips", isOn: $tracksTips)
                } header: {
                    Text("Pay")
                } footer: {
                    Text(target.existing == nil
                         ? "Turn on Tips for a job where you get them — waiting tables, a bar."
                         : "A new rate applies to shifts you log from now on — ones already logged keep theirs.")
                }

                Section {
                    DatePicker("Starts", selection: $checkIn, displayedComponents: .hourAndMinute)
                    DatePicker("Ends", selection: $checkOut, displayedComponents: .hourAndMinute)
                    Toggle("Works weekends", isOn: $worksWeekends)
                } header: {
                    Text("Usual shift")
                } footer: {
                    Text("New shifts start out with these times. Weekends count toward the month's projection when on.")
                }

                Section {
                    HStack {
                        Text("Target")
                        Spacer()
                        TextField("None", text: $goalText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(maxWidth: 110)
                        Text(goalKind.isMoney ? "€" : "h")
                            .foregroundStyle(.secondary)
                            .frame(width: 14, alignment: .leading)
                    }
                    Picker("Goal in", selection: $goalKind.animation(.default)) {
                        ForEach(GoalKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Monthly goal")
                } footer: {
                    Text("Shown as progress on the job's tab and its projection. Leave blank for none.")
                }

                if target.existing != nil {
                    Section {
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Label("Delete job", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .alert("Delete \(trimmedName.isEmpty ? "this job" : trimmedName)?", isPresented: $confirmingDelete) {
                            Button("Delete", role: .destructive) { deleteJob() }
                            Button("Keep", role: .cancel) {}
                        } message: {
                            Text(shiftCount == 0
                                 ? "Its tab goes away."
                                 : "Its tab and all \(Fmt.count(shiftCount, "shift")) logged for it go away. This can't be undone.")
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(target.existing == nil ? "New job" : "Edit job")
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
        .tint(color.color)
    }

    // MARK: - Pieces

    /// The tab-to-be, so colour and icon choices show up as you make them.
    private var preview: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .frame(width: 48, height: 48)
                .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(trimmedName.isEmpty ? "New job" : trimmedName)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                Text(rate > 0 ? "\(Fmt.money(rate))/h\(tracksTips ? " + tips" : "")" : "Set an hourly rate")
                    .font(.subheadline)
                    .opacity(0.85)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(
            LinearGradient(colors: [color.color, color.gradientEnd], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .animation(.snappy, value: color)
    }

    private var colorGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 12) {
            ForEach(JobColor.allCases) { option in
                Button {
                    color = option
                } label: {
                    Circle()
                        .fill(option.color)
                        .frame(width: 40, height: 40)
                        .overlay {
                            if option == color {
                                Image(systemName: "checkmark")
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .overlay(Circle().strokeBorder(Color.primary.opacity(option == color ? 0.25 : 0), lineWidth: 3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(option == color ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }

    private var symbolGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
            ForEach(JobSymbol.all, id: \.self) { option in
                Button {
                    symbol = option
                } label: {
                    Image(systemName: option)
                        .font(.body.weight(.medium))
                        .foregroundStyle(option == symbol ? .white : color.color)
                        .frame(width: 42, height: 42)
                        .background(
                            option == symbol ? AnyShapeStyle(color.color) : AnyShapeStyle(Color(.tertiarySystemFill)),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(option == symbol ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Saving

    private func save() {
        let job: Job
        if let existing = target.existing {
            job = existing
        } else {
            job = Job(name: trimmedName, hourlyRate: rate, sortOrder: (jobs.map(\.sortOrder).max() ?? -1) + 1)
            context.insert(job)
        }

        job.name = trimmedName
        job.colorRaw = color.rawValue
        job.symbol = symbol
        job.hourlyRate = rate
        job.tracksTips = tracksTips
        job.worksWeekends = worksWeekends
        job.defaultCheckInMinutes = Self.minutes(checkIn)
        job.defaultCheckOutMinutes = Self.minutes(checkOut)

        job.goalTarget = goal
        job.goalKind = goalKind

        try? context.save()
        if target.existing == nil {
            selectedTab = job.id.uuidString
        }
        dismiss()
    }

    /// Closes the sheet first and deletes once it's gone, so nothing on screen
    /// is left reading a job that no longer exists.
    private func deleteJob() {
        guard let job = target.existing else { return }
        let context = context
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            AppSetup.delete(job, in: context)
        }
    }

    // MARK: - Time helpers

    private static func date(minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    }

    private static func minutes(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

#Preview {
    JobEditorView(target: .new)
        .modelContainer(PreviewData.container)
}
