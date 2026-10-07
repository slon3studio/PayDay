import SwiftUI
import SwiftData
import Charts

/// Who you are, the jobs you track, and how it all adds up. It's also where a
/// fresh install starts: say a little about yourself, add a job, and every job
/// gets a tab of its own.
struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Job.sortOrder), SortDescriptor(\Job.createdAt)]) private var jobs: [Job]
    @Query(sort: \Shift.checkIn, order: .reverse) private var allShifts: [Shift]

    @AppStorage(UserProfile.nameKey) private var name = ""
    @AppStorage(UserProfile.roleKey) private var role = ""
    @AppStorage(UserProfile.emojiKey) private var emoji = ""
    @AppStorage(UserProfile.colorKey) private var colorRaw = UserProfile.defaultColor.rawValue

    @State private var granularity: Granularity = .month
    @State private var metric: ProfileMetric = .hours
    @State private var showingSettings = false
    @State private var editingProfile = false
    @State private var jobEditor: JobEditorTarget?
    @State private var editMode: EditMode = .inactive

    private var profileColor: JobColor { JobColor(rawValue: colorRaw) ?? UserProfile.defaultColor }

    enum Granularity: String, CaseIterable, Identifiable {
        case week = "Weekly"
        case month = "Monthly"

        var id: String { rawValue }
        var component: Calendar.Component { self == .week ? .weekOfYear : .month }
        var limit: Int { self == .week ? 8 : 6 }
    }

    private func shifts(of job: Job) -> [Shift] {
        allShifts.filter { $0.job?.id == job.id }
    }

    private func stats(_ job: Job) -> ShiftStats {
        ShiftStats(job: job, shifts: shifts(of: job))
    }

    private var totalHours: Double { allShifts.reduce(0) { $0 + $1.hours } }
    private var totalEarnings: Double { allShifts.reduce(0) { $0 + $1.totalPay } }
    private var totalTips: Double { allShifts.reduce(0) { $0 + $1.tipsAmount } }
    private var dayCount: Int { Set(allShifts.map(\.day)).count }

    private var buckets: [StatsEngine.Bucket] {
        StatsEngine.buckets(from: allShifts, jobs: jobs, granularity: granularity.component, limit: granularity.limit)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Profile")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsView()
                }
                .sheet(isPresented: $editingProfile) {
                    ProfileEditorView()
                }
                .sheet(item: $jobEditor) { target in
                    JobEditorView(target: target)
                }
        }
    }

    private var content: some View {
        List {
            Section {
                profileCard
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            jobsSection

            if !allShifts.isEmpty {
                Section {
                    ForEach(jobs) { job in
                        JobProjection(job: job, shifts: shifts(of: job))
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } header: {
                    Text("Projected pay · \(Fmt.monthTitle(.now))")
                }

                Section {
                    totalsCard
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                } header: {
                    Text("All time")
                }

                Section {
                    trendChart
                } header: {
                    Text(jobs.count > 1 ? "Compare" : "Trend")
                } footer: {
                    Text("The last \(granularity.limit) \(granularity == .week ? "weeks" : "months") you've worked.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollBounceBehavior(.basedOnSize)
        // Only the jobs list is movable; this is what shows its drag handles.
        .environment(\.editMode, $editMode)
        .tint(profileColor.color)
    }

    // MARK: - You

    private var profileCard: some View {
        Button {
            editingProfile = true
        } label: {
            HStack(spacing: 14) {
                ProfileAvatar(emoji: emoji, name: name, color: profileColor, size: 60)

                VStack(alignment: .leading, spacing: 3) {
                    Text(name.isEmpty ? "Add your name" : name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(name.isEmpty ? .secondary : .primary)
                    if !role.isEmpty {
                        Text(role)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("Tracking since \(trackingSince.formatted(.dateTime.day().month(.wide).year()))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Your first shift, or the first time the app was opened — whichever was
    /// earlier. History carried over from before profiles beats the install date.
    private var trackingSince: Date {
        min(allShifts.last?.checkIn ?? .distantFuture, UserProfile.started)
    }

    // MARK: - Jobs

    private var jobsSection: some View {
        Section {
            ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                if editMode.isEditing {
                    // Arrows as well as the drag handle: a drag is easy to
                    // miss on a small list, a tap isn't.
                    HStack(spacing: 12) {
                        JobRow(job: job, shiftCount: shifts(of: job).count, showsChevron: false)
                        Button {
                            withAnimation { moveJobs(from: IndexSet(integer: index), to: index - 1) }
                        } label: {
                            Image(systemName: "chevron.up.circle.fill").font(.title2)
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)
                        .accessibilityLabel("Move \(job.displayName) up")
                        Button {
                            withAnimation { moveJobs(from: IndexSet(integer: index), to: index + 2) }
                        } label: {
                            Image(systemName: "chevron.down.circle.fill").font(.title2)
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == jobs.count - 1)
                        .accessibilityLabel("Move \(job.displayName) down")
                    }
                } else {
                    Button {
                        jobEditor = .edit(job)
                    } label: {
                        JobRow(job: job, shiftCount: shifts(of: job).count)
                    }
                    .buttonStyle(.plain)
                }
            }
            .onMove(perform: moveJobs)

            Button {
                jobEditor = .new
            } label: {
                Label(jobs.isEmpty ? "Add your first job" : "Add a job", systemImage: "plus.circle.fill")
                    .font(.body.weight(.semibold))
            }
        } header: {
            HStack {
                Text("Jobs")
                Spacer()
                if jobs.count > 1 {
                    Button(editMode.isEditing ? "Done" : "Reorder") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                    .font(.subheadline.weight(.semibold))
                    .textCase(nil)
                }
            }
        } footer: {
            Text(jobs.isEmpty
                 ? "Each job gets its own tab — with its own colour, hourly rate, usual hours and goal."
                 : editMode.isEditing
                    ? "Use the arrows or drag the handles — the tabs follow this order."
                    : "Tap a job to change its name, colour, rate or goal.")
        }
    }

    /// The tab bar follows `sortOrder`, so a drag here renumbers every job.
    private func moveJobs(from source: IndexSet, to destination: Int) {
        var ordered = jobs
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, job) in ordered.enumerated() {
            job.sortOrder = index
        }
        try? modelContext.save()
    }

    // MARK: - Totals

    private var totalsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total earned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Fmt.money(totalEarnings))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(.green)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }

            StatGrid {
                StatTile(
                    title: "Total hours",
                    value: Fmt.hours(totalHours),
                    caption: "\(Fmt.count(dayCount, "day")) · \(Fmt.count(allShifts.count, "shift"))",
                    background: Color(.tertiarySystemFill)
                )
                if jobs.contains(where: \.tracksTips) {
                    let tipped = allShifts.filter { $0.job?.tracksTips == true }
                    StatTile(
                        title: "Tips",
                        value: Fmt.money(totalTips),
                        caption: "Avg \(Fmt.money(tipped.isEmpty ? 0 : totalTips / Double(tipped.count)))/shift",
                        background: Color(.tertiarySystemFill)
                    )
                } else {
                    StatTile(
                        title: "Avg per day",
                        value: Fmt.hours(dayCount == 0 ? 0 : totalHours / Double(dayCount)),
                        background: Color(.tertiarySystemFill)
                    )
                }
                // With one job its tile would only repeat the totals above.
                if jobs.count > 1 {
                    ForEach(jobs) { job in
                        let s = stats(job)
                        StatTile(
                            title: job.displayName,
                            value: Fmt.money(s.totalEarnings),
                            caption: "\(Fmt.hours(s.totalHours)) · avg \(Fmt.hours(s.averageHoursPerDay))/day",
                            tint: job.tint,
                            background: Color(.tertiarySystemFill)
                        )
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var trendChart: some View {
        VStack(spacing: 12) {
            Picker("Metric", selection: $metric.animation(.default)) {
                ForEach(ProfileMetric.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("Granularity", selection: $granularity.animation(.default)) {
                ForEach(Granularity.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Chart {
                ForEach(buckets) { bucket in
                    ForEach(jobs) { job in
                        BarMark(
                            x: .value("Period", bucket.label),
                            y: .value(metric.rawValue, bucket.value(for: job, metric: metric))
                        )
                        .foregroundStyle(by: .value("Job", job.displayName))
                        .position(by: .value("Job", job.displayName))
                        .cornerRadius(4)
                    }
                }
            }
            .chartForegroundStyleScale(domain: jobs.map(\.displayName), range: jobs.map(\.tint))
            .chartLegend(jobs.count > 1 ? .visible : .hidden)
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let raw = value.as(Double.self) {
                            Text(metric == .hours ? "\(Int(raw))h" : "€\(Int(raw))")
                        }
                    }
                }
            }
            .frame(height: 220)
        }
        .padding(.vertical, 4)
    }
}

/// A job in the Profile's list: its colour and icon, name, and rate.
private struct JobRow: View {
    let job: Job
    let shiftCount: Int
    var showsChevron = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: job.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(job.tint, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(job.displayName)
                    .font(.body.weight(.medium))
                Text("\(Fmt.money(job.hourlyRate))/h\(job.tracksTips ? " · tips" : "") · \(Fmt.count(shiftCount, "shift"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

/// One job's projection, with the remaining-days basis remembered per job —
/// a weekday desk job and a weekend waiting job want different bases.
private struct JobProjection: View {
    let job: Job
    let shifts: [Shift]

    @AppStorage private var basisRaw: String

    init(job: Job, shifts: [Shift]) {
        self.job = job
        self.shifts = shifts
        let fallback: ProjectionBasis = job.worksWeekends ? .pattern : .weekdays
        _basisRaw = AppStorage(wrappedValue: fallback.rawValue, job.projectionBasisKey)
    }

    private var basis: Binding<ProjectionBasis> {
        Binding(
            get: { ProjectionBasis(rawValue: basisRaw) ?? .weekdays },
            set: { basisRaw = $0.rawValue }
        )
    }

    var body: some View {
        ProjectionCard(
            projection: StatsEngine.projection(for: job, allShiftsForJob: shifts, basis: basis.wrappedValue),
            basis: basis
        )
    }
}

// MARK: - Your profile

/// Your emoji, or your initials when there's no emoji, on your colour.
struct ProfileAvatar: View {
    let emoji: String
    let name: String
    let color: JobColor
    var size: CGFloat = 60

    /// Up to two letters from the name, or a face when there isn't one yet.
    private var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "🙂" : String(letters).uppercased()
    }

    var body: some View {
        Text(emoji.isEmpty ? initials : emoji)
            .font(.system(size: size * (emoji.isEmpty ? 0.38 : 0.5), weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [color.color, color.gradientEnd], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Circle()
            )
    }
}

/// Who you are: an emoji, a name, what you do, and your colour. Changes apply
/// as you make them.
struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(UserProfile.nameKey) private var name = ""
    @AppStorage(UserProfile.roleKey) private var role = ""
    @AppStorage(UserProfile.emojiKey) private var emoji = ""
    @AppStorage(UserProfile.colorKey) private var colorRaw = UserProfile.defaultColor.rawValue

    private var color: JobColor { JobColor(rawValue: colorRaw) ?? UserProfile.defaultColor }

    private static let emojis = [
        "🙂", "😎", "🤓", "🥳", "😺", "🐱", "🦊", "🐶", "🐼", "🐸",
        "🦁", "🐧", "🧑‍💻", "👩‍💻", "👨‍💻", "🧑‍🍳", "👩‍🎓", "🧑‍🎨", "☕️", "🍕",
        "🎧", "🎨", "📚", "💼", "🚀", "⚡️", "🔥", "🌈", "🍀", "🌻",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        ProfileAvatar(emoji: emoji, name: name, color: color, size: 88)
                        Text(name.isEmpty ? "Your name" : name)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(name.isEmpty ? .secondary : .primary)
                        if !role.isEmpty {
                            Text(role)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                    .animation(.snappy, value: emoji)
                    .animation(.snappy, value: colorRaw)
                }

                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                    TextField("What you do — e.g. Student", text: $role)
                } header: {
                    Text("You")
                } footer: {
                    Text("Only kept on this phone. No account needed.")
                }

                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                        ForEach(Self.emojis, id: \.self) { option in
                            Button {
                                emoji = option
                            } label: {
                                Text(option)
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        option == emoji ? AnyShapeStyle(color.color.opacity(0.25)) : AnyShapeStyle(Color.clear),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(option == emoji ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)

                    if !emoji.isEmpty {
                        Button("Use my initials instead") { emoji = "" }
                    }
                } header: {
                    Text("Emoji")
                }

                Section("Colour") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 12) {
                        ForEach(JobColor.allCases) { option in
                            Button {
                                colorRaw = option.rawValue
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
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.label)
                            .accessibilityAddTraits(option == color ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(color.color)
    }
}

// MARK: - Settings

/// How the app looks. Your details live behind the profile card; each job's
/// settings in its editor.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Appearance.key) private var appearanceRaw: String = Appearance.system.rawValue
    @AppStorage(AppSettings.currencyKey) private var currencyCode = AppSettings.deviceDefault

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearanceRaw) {
                        ForEach(Appearance.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Picker("Currency", selection: $currencyCode) {
                        ForEach(AppSettings.currencies, id: \.self) { code in
                            Text("\(code) · \(AppSettings.name(for: code))").tag(code)
                        }
                    }
                } header: {
                    Text("Currency")
                } footer: {
                    Text("Changes how every amount is shown. Nothing already logged is converted — the numbers stay as you entered them.")
                }

                Section {
                    LabeledContent {
                        Text(StoreStatus.isSyncing ? "On" : "Off")
                            .foregroundStyle(StoreStatus.isSyncing ? .green : .orange)
                    } label: {
                        Label("iCloud sync", systemImage: StoreStatus.isSyncing ? "checkmark.icloud" : "xmark.icloud")
                    }
                } header: {
                    Text("Sync")
                } footer: {
                    Text(StoreStatus.isSyncing
                         ? "Your jobs and shifts are kept on every device signed in to the same Apple Account."
                         : "This phone couldn't reach iCloud, so everything is being kept here only. Nothing is lost — check that you're signed in and that iCloud Drive is on, then reopen PayDay.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ProfileView()
        .modelContainer(PreviewData.container)
}
