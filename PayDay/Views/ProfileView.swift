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

    private var monthShifts: [Shift] { StatsEngine.shifts(allShifts, in: .month) }
    private var monthEarnings: Double { monthShifts.reduce(0) { $0 + $1.totalPay } }
    private var monthHours: Double { monthShifts.reduce(0) { $0 + $1.hours } }
    private var monthDays: Int { Set(monthShifts.map(\.day)).count }

    private func monthEarnings(of job: Job) -> Double {
        monthShifts.filter { $0.job?.id == job.id }.reduce(0) { $0 + $1.totalPay }
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
                profileHeader
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
                    SectionHeader("Projected pay · \(Fmt.monthTitle(.now))")
                }

                Section {
                    trendChart
                } header: {
                    SectionHeader(jobs.count > 1 ? "Compare" : "Trend")
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

    /// Identity and this month in one card, in the app's own green — the
    /// counterpart to the gradient card each job tab opens with. Profile used
    /// to be a white row with a name in it, which looked like a settings
    /// screen wearing the app's clothes.
    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button {
                editingProfile = true
            } label: {
                HStack(spacing: 12) {
                    ProfileAvatar(emoji: emoji, name: name, color: profileColor, size: 46, onColour: true)
                        .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 2))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(name.isEmpty ? "Add your name" : name)
                            .font(.headline)
                        Text(subtitle)
                            .font(.caption)
                            .opacity(0.85)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .opacity(0.7)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.money(monthEarnings))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("earned in \(Fmt.monthTitle(.now))\(jobs.count > 1 ? ", across every job" : "")")
                    .font(.subheadline)
                    .opacity(0.85)
            }

            HStack(spacing: 0) {
                headerStat("Hours", Fmt.hours(monthHours))
                headerDivider
                headerStat("Days", "\(monthDays)")
                headerDivider
                headerStat(jobs.count == 1 ? "Job" : "Jobs", "\(jobs.count)")
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [profileColor.color, profileColor.gradientEnd],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous)
        )
    }

    /// What goes under the name: the role if there is one, otherwise how long
    /// you've been at it — and nothing at all in the first week.
    private var subtitle: String {
        if !role.isEmpty { return role }
        if hasHistory {
            return "Tracking since \(trackingSince.formatted(.dateTime.month(.abbreviated).year()))"
        }
        return jobs.isEmpty ? "No jobs yet" : Fmt.count(jobs.count, "job")
    }

    private func headerStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .opacity(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.3))
            .frame(width: 1, height: 28)
            .padding(.trailing, 12)
    }

    /// Your first shift, or the first time the app was opened — whichever was
    /// earlier. History carried over from before profiles beats the install date.
    private var trackingSince: Date {
        min(allShifts.last?.checkIn ?? .distantFuture, UserProfile.started)
    }

    /// A week is roughly when "since" starts meaning something.
    private var hasHistory: Bool {
        trackingSince < Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    }

    // MARK: - Jobs

    private var jobsSection: some View {
        Section {
            ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                if editMode.isEditing {
                    // Arrows as well as the drag handle: a drag is easy to
                    // miss on a small list, a tap isn't.
                    HStack(spacing: 12) {
                        JobRow(job: job, shiftCount: shifts(of: job).count, monthEarnings: monthEarnings(of: job), showsChevron: false)
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
                        JobRow(job: job, shiftCount: shifts(of: job).count, monthEarnings: monthEarnings(of: job))
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
    let monthEarnings: Double
    var showsChevron = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: job.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    LinearGradient(colors: [job.tint, job.gradientEnd],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: Palette.tileRadius, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(job.displayName)
                    .font(.body.weight(.medium))
                Text("\(Fmt.money(job.hourlyRate))/h\(job.tracksTips ? " · tips" : "") · \(Fmt.count(shiftCount, "shift"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if monthEarnings > 0 {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Fmt.money(monthEarnings))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.money)
                    Text("this month")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

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
/// Everything you've earned, ever — behind the profile card rather than on
/// the tab, which is about the month in front of you.
struct AllTimeCard: View {
    let jobs: [Job]
    let shifts: [Shift]

    private var totalEarnings: Double { shifts.reduce(0) { $0 + $1.totalPay } }
    private var totalHours: Double { shifts.reduce(0) { $0 + $1.hours } }
    private var totalTips: Double { shifts.reduce(0) { $0 + $1.tipsAmount } }
    private var dayCount: Int { Set(shifts.map(\.day)).count }

    private func stats(_ job: Job) -> ShiftStats {
        ShiftStats(job: job, shifts: shifts.filter { $0.job?.id == job.id })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total earned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Fmt.money(totalEarnings))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(Palette.money)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }

            StatGrid {
                StatTile(
                    title: "Total hours",
                    value: Fmt.hours(totalHours),
                    caption: "\(Fmt.count(dayCount, "day")) · \(Fmt.count(shifts.count, "shift"))",
                    background: Color(.tertiarySystemFill)
                )
                if jobs.contains(where: \.tracksTips) {
                    let tipped = shifts.filter { $0.job?.tracksTips == true }
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
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous))
    }
}

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
    /// Sitting on a coloured card rather than a grey one.
    var onColour = false

    /// Up to two letters from the name. With no name there's nothing to
    /// abbreviate, so the avatar invites you to set one instead.
    private var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return String(letters).uppercased()
    }

    private var isEmpty: Bool { emoji.isEmpty && initials.isEmpty }

    var body: some View {
        Group {
            if isEmpty {
                Image(systemName: "plus")
                    .font(.system(size: size * 0.34, weight: .bold))
            } else {
                Text(emoji.isEmpty ? initials : emoji)
                    .font(.system(size: size * (emoji.isEmpty ? 0.38 : 0.5), weight: .bold, design: .rounded))
            }
        }
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background {
                if onColour {
                    Circle().fill(.white.opacity(0.22))
                } else {
                    Circle().fill(LinearGradient(colors: [color.color, color.gradientEnd],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
    }
}

/// Who you are: an emoji, a name, what you do, and your colour. Changes apply
/// as you make them.
/// Who you are, and everything you've earned. A wall of thirty emoji made
/// this look like a sticker picker; it's now a short, restrained row that
/// previews the avatar itself rather than offering a keyboard.
struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\Job.sortOrder), SortDescriptor(\Job.createdAt)]) private var jobs: [Job]
    @Query(sort: \Shift.checkIn, order: .reverse) private var allShifts: [Shift]

    @AppStorage(UserProfile.nameKey) private var name = ""
    @AppStorage(UserProfile.roleKey) private var role = ""
    @AppStorage(UserProfile.emojiKey) private var emoji = ""
    @AppStorage(UserProfile.colorKey) private var colorRaw = UserProfile.defaultColor.rawValue

    private var color: JobColor { JobColor(rawValue: colorRaw) ?? UserProfile.defaultColor }

    /// Kept short and even-tempered. The long list was the problem.
    private static let emojis = ["🙂", "😎", "🧑‍💻", "🧑‍🍳", "🎧", "☕️", "📚", "⚡️"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    header
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    LabeledContent("Name") {
                        TextField("Your name", text: $name)
                            .textContentType(.name)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Role") {
                        TextField("Optional", text: $role)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Kept on this phone and in your own iCloud. There is no account.")
                }

                Section {
                    avatarRow
                    colourRow
                } header: {
                    SectionHeader("Appearance")
                } footer: {
                    Text("Your colour tints the Profile tab.")
                }

                if !allShifts.isEmpty {
                    Section {
                        AllTimeCard(jobs: jobs, shifts: allShifts)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                            .listRowBackground(Color.clear)
                    } header: {
                        SectionHeader("All time")
                    } footer: {
                        Text("Everything logged since you started, across every job.")
                    }
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

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 10) {
            ProfileAvatar(emoji: emoji, name: name, color: color, size: 88)
            VStack(spacing: 2) {
                Text(name.isEmpty ? "Your name" : name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(name.isEmpty ? .secondary : .primary)
                if !role.isEmpty {
                    Text(role)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .animation(.snappy, value: emoji)
        .animation(.snappy, value: colorRaw)
    }

    /// Each option drawn as the avatar it would produce, so the row is a
    /// preview rather than a list of characters.
    private var avatarRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Avatar")
                .font(.subheadline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    swatch(isSelected: emoji.isEmpty) {
                        emoji = ""
                    } content: {
                        Text(initials.isEmpty ? "AB" : initials)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .opacity(initials.isEmpty ? 0.5 : 1)
                    }

                    ForEach(Self.emojis, id: \.self) { option in
                        swatch(isSelected: option == emoji) {
                            emoji = option
                        } content: {
                            Text(option).font(.title3)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 4)
    }

    private func swatch<Content: View>(
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            content()
                .frame(width: 44, height: 44)
                .background(
                    LinearGradient(colors: [color.color, color.gradientEnd],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Circle()
                )
                .overlay(Circle().strokeBorder(Color.primary.opacity(isSelected ? 0.9 : 0), lineWidth: 2))
                .padding(2)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var colourRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Colour")
                .font(.subheadline)

            HStack(spacing: 0) {
                ForEach(JobColor.allCases) { option in
                    Button {
                        colorRaw = option.rawValue
                    } label: {
                        Circle()
                            .fill(option.color)
                            .frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(.background, lineWidth: option == color ? 2 : 0))
                            .overlay(Circle().strokeBorder(Color.primary.opacity(option == color ? 0.9 : 0), lineWidth: 2)
                                .padding(-3))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.label)
                    .accessibilityAddTraits(option == color ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var initials: String {
        String(name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
    }
}

/// Settings is about the app; the profile card is about you.
///
/// That line decides what lives where. How amounts are shown, which theme,
/// whether iCloud is running and what version this is are all facts about
/// PayDay. Your name, what you do, your avatar and what you have earned are
/// facts about you, and live one tap into the profile card instead.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Appearance.key) private var appearanceRaw: String = Appearance.system.rawValue
    @AppStorage(AppSettings.currencyKey) private var currencyCode = AppSettings.deviceDefault

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    displayCard
                    syncCard
                    aboutCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Palette.brand)
    }

    // MARK: - Cards

    private var displayCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle("Display")

            VStack(alignment: .leading, spacing: 8) {
                Text("Theme")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("Theme", selection: $appearanceRaw) {
                    ForEach(Appearance.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)

            Divider().padding(.leading, 16)

            HStack {
                Label("Currency", systemImage: "coloncurrencysign.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $currencyCode) {
                    ForEach(AppSettings.currencies, id: \.self) { code in
                        Text("\(code) · \(AppSettings.name(for: code))").tag(code)
                    }
                }
                .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            footnote("Changes how every amount is shown. Nothing already logged is converted — the numbers stay as you entered them.")
        }
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous))
    }

    private var syncCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle("iCloud")

            HStack(spacing: 12) {
                SymbolTile(symbol: StoreStatus.isSyncing ? "checkmark.icloud.fill" : "xmark.icloud.fill",
                           colour: StoreStatus.isSyncing ? Palette.money : Palette.attention,
                           size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(StoreStatus.isSyncing ? "Syncing" : "This phone only")
                        .font(.body.weight(.medium))
                    Text(StoreStatus.isSyncing ? "Every device on your Apple Account" : "iCloud couldn't be reached")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            footnote(StoreStatus.isSyncing
                     ? "Your jobs and shifts are kept in your own private iCloud. Nobody else can read them — not even us."
                     : "Nothing is lost. Check that you're signed in to iCloud and that iCloud Drive is on, then reopen PayDay.")
        }
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous))
    }

    private var aboutCard: some View {
        VStack(spacing: 10) {
            PayDayMark(size: 52)
            Text("PayDay \(Bundle.main.shortVersion)")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
            Text("No account. No ads. No tracking.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous))
    }

    private func cardTitle(_ text: String) -> some View {
        SectionHeader(text)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            .padding(.top, 2)
    }
}
