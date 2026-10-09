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
    @State private var tracksBreaks: Bool
    @State private var breakMinutes: Int
    @State private var confirmingDelete = false
    /// A new job starts on the template grid; picking one — or skipping —
    /// drops into the form. Editing an existing job never shows it.
    @State private var choosingTemplate: Bool

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
        _tracksBreaks = State(initialValue: job?.tracksBreaks ?? false)
        _breakMinutes = State(initialValue: job?.defaultBreakMinutes ?? 30)
        _choosingTemplate = State(initialValue: job == nil)
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
            Group {
                if choosingTemplate {
                    templateChooser
                } else {
                    form
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if !choosingTemplate {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(!canSave)
                    }
                }
            }
        }
        .tint(target.existing?.tint ?? Palette.brand)
    }

    private var navigationTitle: String {
        if choosingTemplate { return "What kind of work?" }
        return target.existing == nil ? "New job" : "Edit job"
    }

    // MARK: - Template step

    /// Eight kinds of work, and a way past them. Picking one fills in the
    /// whole form; nothing is saved until you press Save on the next screen,
    /// so a wrong guess costs a tap.
    private var templateChooser: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("Pick the closest one and we'll fill in the usual hours, colour and icon. You can change all of it on the next screen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                    ForEach(JobTemplate.all) { template in
                        Button { apply(template) } label: { tile(template) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)

                Button {
                    apply(JobTemplate.blank)
                } label: {
                    Text("Something else")
                        .font(.subheadline.weight(.medium))
                        .padding(.vertical, 10)
                }
                .padding(.bottom, 24)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private func tile(_ template: JobTemplate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: template.symbol)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    LinearGradient(colors: [template.color.color, template.color.gradientEnd],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )

            Text(template.label)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(Self.summary(template))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// "17:00-23:30 - tips" — what the template is actually setting, so the
    /// tile isn't just a pretty label.
    private static func summary(_ template: JobTemplate) -> String {
        var parts = ["\(hhmm(template.checkIn))-\(hhmm(template.checkOut))"]
        if template.tracksTips { parts.append("tips") }
        if template.tracksBreaks { parts.append("\(template.breakMinutes)m break") }
        return parts.joined(separator: " · ")
    }

    private static func hhmm(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    private func apply(_ template: JobTemplate) {
        color = template.color
        symbol = template.symbol
        tracksTips = template.tracksTips
        worksWeekends = template.worksWeekends
        tracksBreaks = template.tracksBreaks
        if template.breakMinutes > 0 { breakMinutes = template.breakMinutes }
        checkIn = Self.date(minutes: template.checkIn)
        checkOut = Self.date(minutes: template.checkOut)
        Haptics.tap()
        withAnimation(.snappy) { choosingTemplate = false }
    }

    private var form: some View {
        ScrollView {
            VStack(spacing: 16) {
                preview
                nameCard
                appearanceCard
                payCard
                shiftCard
                breakCard
                goalCard
                if target.existing != nil { deleteButton }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Cards

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow("Name", opacity: 1).foregroundStyle(.secondary)
            TextField("Café, Office, Tutoring…", text: $name)
                .font(.title3.weight(.semibold))
            Text("Shown on its tab. Emoji welcome.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("Colour", opacity: 1).foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    ForEach(JobColor.allCases) { option in
                        Button { color = option } label: {
                            Circle()
                                .fill(option.color)
                                .frame(width: 26, height: 26)
                                .overlay(Circle().strokeBorder(.background, lineWidth: option == color ? 2 : 0))
                                .overlay(Circle()
                                    .strokeBorder(Color.primary.opacity(option == color ? 0.9 : 0), lineWidth: 2)
                                    .padding(-3))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.label)
                        .accessibilityAddTraits(option == color ? .isSelected : [])
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().padding(.leading, 16)

            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("Icon", opacity: 1).foregroundStyle(.secondary)
                symbolGrid
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous))
    }

    private var payCard: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Hourly rate", systemImage: "eurosign.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("0", text: $rateText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: 110)
                Text("€/h")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().padding(.leading, 16)

            Toggle(isOn: $tracksTips.animation(.snappy)) {
                Label("Tips", systemImage: "banknote")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            footnote(target.existing == nil
                     ? "Turn Tips on for a job where you get them — waiting tables, a bar."
                     : "A new rate applies to shifts logged from now on; ones already logged keep theirs.")
        }
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous))
    }

    private var shiftCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                timeBlock("Starts", selection: $checkIn)
                Rectangle()
                    .fill(Color(.separator).opacity(0.5))
                    .frame(width: 1, height: 46)
                timeBlock("Ends", selection: $checkOut)
            }
            .padding(.vertical, 14)

            Divider().padding(.leading, 16)

            Toggle(isOn: $worksWeekends) {
                Label("Works weekends", systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            footnote("New shifts start out with these times. Weekends count toward the month's projection when on.")
        }
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous))
    }

    private func timeBlock(_ label: String, selection: Binding<Date>) -> some View {
        VStack(spacing: 4) {
            Eyebrow(label, opacity: 1)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
        .frame(maxWidth: .infinity)
    }

    private var breakCard: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $tracksBreaks.animation(.snappy)) {
                Label("Unpaid break", systemImage: "cup.and.saucer")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if tracksBreaks {
                Divider().padding(.leading, 16)
                HStack {
                    Text("Usually")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $breakMinutes) {
                        ForEach([15, 20, 30, 45, 60], id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            footnote(tracksBreaks
                     ? "Taken off the hours a shift counts for, and changeable per shift. Shifts already logged keep the hours they were logged with."
                     : "Leave off if your break is paid, or if there isn't one.")
        }
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous))
    }

    private var goalCard: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Monthly target", systemImage: "target")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("None", text: $goalText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: 110)
                Text(goalKind.isMoney ? "€" : "h")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().padding(.leading, 16)

            Picker("Goal in", selection: $goalKind.animation(.default)) {
                ForEach(GoalKind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            footnote("Shown as progress on the job's tab and its projection. Leave blank for none.")
        }
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous))
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            confirmingDelete = true
        } label: {
            Label("Delete job", systemImage: "trash")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous))
        .alert("Delete \(trimmedName.isEmpty ? "this job" : trimmedName)?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { deleteJob() }
            Button("Keep", role: .cancel) {}
        } message: {
            Text(shiftCount == 0
                 ? "Its tab goes away."
                 : "Its tab and all \(Fmt.count(shiftCount, "shift")) logged for it go away. This can't be undone.")
        }
    }

    /// The explanatory line a Form would have put under the section.
    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .padding(.top, 2)
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
        job.tracksBreaks = tracksBreaks
        job.defaultBreakMinutes = breakMinutes

        job.goalTarget = goal
        job.goalKind = goalKind

        try? context.save()
        Haptics.success()
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
