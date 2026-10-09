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

    private var profileColor: JobColor { JobColor(rawValue: colorRaw) ?? UserProfile.defaultColor }

    @State private var granularity: Granularity = .month
    @State private var metric: ProfileMetric = .hours
    @State private var showingSettings = false
    @State private var editingProfile = false
    @State private var jobEditor: JobEditorTarget?
    @State private var editMode: EditMode = .inactive


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
        ShiftStats(job: job, shifts: shifts(of: job).logged)
    }

    /// Worked shifts only — a plan isn't earnings.
    private var monthShifts: [Shift] { StatsEngine.shifts(allShifts, in: .month).logged }
    private var monthEarnings: Double { monthShifts.reduce(0) { $0 + $1.totalPay } }
    private var monthHours: Double { monthShifts.reduce(0) { $0 + $1.hours } }
    private var monthDays: Int { Set(monthShifts.map(\.day)).count }

    private func monthEarnings(of job: Job) -> Double {
        monthShifts.filter { $0.job?.id == job.id }.reduce(0) { $0 + $1.totalPay }
    }

    private var totalHours: Double { allShifts.logged.reduce(0) { $0 + $1.hours } }
    private var totalEarnings: Double { allShifts.logged.reduce(0) { $0 + $1.totalPay } }
    private var totalTips: Double { allShifts.logged.reduce(0) { $0 + $1.tipsAmount } }
    private var dayCount: Int { Set(allShifts.map(\.day)).count }

    private var buckets: [StatsEngine.Bucket] {
        StatsEngine.buckets(from: allShifts, jobs: jobs, granularity: granularity.component, limit: granularity.limit)
    }

    var body: some View {
        NavigationStack {
            content
                // Same as the job tabs: the title and its one action are a
                // row of content, so the bar above them was only height.
                .toolbar(.hidden, for: .navigationBar)
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
                HStack {
                    Text("Profile")
                        .font(.largeTitle.bold())
                        // A grouped list clips each row at the card's edge,
                        // and a rounded "g" or "j" at this size hangs well
                        // past the left of its typographic box — the tail was
                        // being sliced off. Indenting the text keeps the whole
                        // glyph inside the clip.
                        .padding(.leading, 10)

                    Spacer(minLength: 12)

                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(profileColor.color)
                            .frame(width: 38, height: 38)
                            .background(profileColor.color.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Settings")
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 1, bottom: 0, trailing: 4))
                .listRowBackground(Color.clear)
            }

            Section {
                profileHeader
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            if !allShifts.isEmpty {
                Section {
                    outlookCard
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                } header: {
                    SectionHeader("Outlook · \(Fmt.monthTitle(.now))")
                }

                Section {
                    ForEach(jobs) { job in
                        JobProjection(job: job, shifts: shifts(of: job), accent: profileColor.color)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } header: {
                    SectionHeader(jobs.count > 1 ? "By job" : "Detail")
                }

                Section {
                    trendChart
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                } header: {
                    SectionHeader(jobs.count > 1 ? "Compare" : "Trend")
                }
            }

            jobsSection
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollBounceBehavior(.basedOnSize)
        // Only the jobs list is movable; this is what shows its drag handles.
        .environment(\.editMode, $editMode)
    }

    // MARK: - You

    // MARK: - Outlook

    private func projection(of job: Job) -> MonthProjection {
        let basis = ProjectionBasis(rawValue: UserDefaults.standard.string(forKey: job.projectionBasisKey) ?? "")
            ?? .pattern
        return StatsEngine.projection(for: job, allShiftsForJob: shifts(of: job), basis: basis)
    }

    private var projections: [(job: Job, projection: MonthProjection)] {
        jobs.map { ($0, projection(of: $0)) }
    }

    /// Where the month lands across every job.
    ///
    /// The headline gets a treatment nothing else on the screen has — the
    /// three parts are one bar rather than three rows, so the proportion of
    /// fact to guess is visible before a single number is read.
    private var outlookCard: some View {
        let all = projections
        let total = all.reduce(0) { $0 + $1.projection.projectedTotal }
        let worked = all.reduce(0) { $0 + $1.projection.payToDate }
        let planned = all.reduce(0) { $0 + $1.projection.plannedPay }
        let estimated = max(0, total - worked - planned)

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Eyebrow("Projected total", opacity: 1)
                    .foregroundStyle(profileColor.color)
                Text(Fmt.money(total))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("by the end of \(Fmt.monthTitle(.now))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if total > 0 {
                ProportionBar(parts: [
                    .init(value: worked, colour: Palette.money, style: .solid),
                    .init(value: planned, colour: Palette.money, style: .half),
                    .init(value: estimated, colour: Palette.money, style: .faint),
                ])
            }

            HStack(spacing: 0) {
                outlookPart("Worked", worked, .solid)
                outlookPart("Planned", planned, .half)
                outlookPart("Estimated", estimated, .faint)
            }

            if jobs.count > 1 {
                Divider()
                VStack(spacing: 8) {
                    ForEach(all, id: \.job.id) { entry in
                        HStack(spacing: 8) {
                            Circle().fill(entry.job.tint).frame(width: 7, height: 7)
                            Text(entry.job.displayName).font(.subheadline)
                            Spacer(minLength: 8)
                            Text(Fmt.money(entry.projection.projectedTotal))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(entry.job.tint)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay {
                    // A wash of your colour from the top, so the card carrying
                    // the headline isn't the same slab as the ones under it.
                    RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous)
                        .fill(LinearGradient(colors: [profileColor.color.opacity(0.10), .clear],
                                             startPoint: .top, endPoint: .bottom))
                }
        }
    }

    private func outlookPart(_ label: String, _ amount: Double, _ style: ProportionBar.Style) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Capsule()
                    .fill(Palette.money.opacity(style.opacity))
                    .frame(width: 10, height: 4)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(Fmt.money(amount))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Identity and this month in one card, in the app's own green — the
    /// counterpart to the gradient card each job tab opens with. Profile used
    /// to be a white row with a name in it, which looked like a settings
    /// screen wearing the app's clothes.
    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
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
        .contentShape(Rectangle())
        .onTapGesture { editingProfile = true }
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
                    HStack(spacing: 10) {
                        JobRow(job: job, shiftCount: shifts(of: job).logged.count, showsChevron: false)
                        VStack(spacing: 6) {
                            Button {
                                withAnimation { moveJobs(from: IndexSet(integer: index), to: index - 1) }
                            } label: {
                                Image(systemName: "chevron.up.circle.fill").font(.title3)
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == 0)
                            .accessibilityLabel("Move \(job.displayName) up")
                            Button {
                                withAnimation { moveJobs(from: IndexSet(integer: index), to: index + 2) }
                            } label: {
                                Image(systemName: "chevron.down.circle.fill").font(.title3)
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == jobs.count - 1)
                            .accessibilityLabel("Move \(job.displayName) down")
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    Button {
                        jobEditor = .edit(job)
                    } label: {
                        JobRow(job: job, shiftCount: shifts(of: job).logged.count)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .onMove(perform: moveJobs)

            Button {
                jobEditor = .new
            } label: {
                AddJobRow(first: jobs.isEmpty, tint: profileColor.color)
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            HStack {
                SectionHeader("Jobs")
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

    /// The last few periods, as a card rather than two stock pickers stacked
    /// over a stock chart. The headline is the total for the window you're
    /// looking at, so the bars are a shape to read rather than the only
    /// content; the legend doubles as a per-job total.
    private var trendChart: some View {
        let windowTotal = buckets.reduce(0.0) { running, bucket in
            running + jobs.reduce(0.0) { $0 + bucket.value(for: $1, metric: metric) }
        }
        // Left to itself the chart rounds the ceiling up to the next round
        // number, which left a third of the card empty above the bars.
        let tallest = buckets.flatMap { bucket in
            jobs.map { bucket.value(for: $0, metric: metric) }
        }.max() ?? 0

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Eyebrow(metric == .hours ? "Hours logged" : "Earned", opacity: 1)
                        .foregroundStyle(.secondary)
                    Text(metric == .hours ? Fmt.hours(windowTotal) : Fmt.money(windowTotal))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("across the last \(granularity.limit) \(granularity == .week ? "weeks" : "months")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                ChipPicker(
                    options: [.init(Granularity.week, "W"), .init(Granularity.month, "M")],
                    selection: $granularity,
                    tint: profileColor.color
                )
            }

            Chart {
                ForEach(buckets) { bucket in
                    ForEach(jobs) { job in
                        BarMark(
                            x: .value("Period", bucket.label),
                            y: .value(metric.rawValue, bucket.value(for: job, metric: metric)),
                            width: .fixed(jobs.count > 1 ? 10 : 18)
                        )
                        .foregroundStyle(by: .value("Job", job.displayName))
                        .position(by: .value("Job", job.displayName))
                        .cornerRadius(5)
                    }
                }
            }
            .chartForegroundStyleScale(domain: jobs.map(\.displayName), range: jobs.map(\.tint))
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel {
                        if let raw = value.as(Double.self) {
                            Text(metric == .hours ? "\(Int(raw))h" : Fmt.compactMoney(raw))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.secondary.opacity(0.6))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.secondary)
                }
            }
            .chartYScale(domain: 0...max(tallest * 1.12, 1))
            .frame(height: 170)

            // The legend carries each job's total for the window, which is the
            // comparison the section is named after.
            if jobs.count > 1 {
                Divider()
                VStack(spacing: 8) {
                    ForEach(jobs) { job in
                        let value = buckets.reduce(0.0) { $0 + $1.value(for: job, metric: metric) }
                        HStack(spacing: 8) {
                            Circle().fill(job.tint).frame(width: 7, height: 7)
                            Text(job.displayName).font(.subheadline)
                            Spacer(minLength: 8)
                            Text(metric == .hours ? Fmt.hours(value) : Fmt.money(value))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(job.tint)
                        }
                    }
                }
            }

            ChipPicker(
                options: [.init(ProfileMetric.hours, "Hours"), .init(ProfileMetric.earnings, "Earned")],
                selection: $metric,
                tint: profileColor.color
            )
            .frame(maxWidth: .infinity)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous))
        .animation(.snappy, value: metric)
        .animation(.snappy, value: granularity)
    }
}

/// A job on the Profile tab: a card in that job's colour, because that colour
/// is what the job's own tab is wearing. The facts underneath are chips rather
/// than a comma-separated line — the rate is the one you'd look for, so it is
/// the one carrying the colour.
private struct JobRow: View {
    let job: Job
    let shiftCount: Int
    var showsChevron = true

    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [job.tint, job.gradientEnd],
                           startPoint: .top, endPoint: .bottom)
                .frame(width: 5)

            HStack(spacing: 12) {
                Image(systemName: job.symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(
                        LinearGradient(colors: [job.tint, job.gradientEnd],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: Palette.tileRadius, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(job.displayName)
                        .font(.system(.body, design: .rounded).weight(.semibold))

                    HStack(spacing: 5) {
                        chip("\(Fmt.money(job.hourlyRate))/h", tint: job.tint)
                        if job.tracksTips { chip("Tips") }
                        chip(Fmt.count(shiftCount, "shift"))
                    }
                }

                Spacer(minLength: 8)

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous)
                        .fill(LinearGradient(colors: [job.tint.opacity(0.10), .clear],
                                             startPoint: .leading, endPoint: .trailing))
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous))
        .contentShape(Rectangle())
    }

    private func chip(_ text: String, tint: Color? = nil) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(tint ?? Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background((tint ?? Color.secondary).opacity(tint == nil ? 0.10 : 0.14), in: Capsule())
    }
}

/// The last row of the jobs list. A dashed outline rather than a filled card,
/// so it reads as a slot waiting to be filled rather than as a job you have.
private struct AddJobRow: View {
    let first: Bool
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.body.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: Palette.tileRadius, style: .continuous))

            Text(first ? "Add your first job" : "Add a job")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(tint)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(tint.opacity(0.35))
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
    /// Your colour, so this card is the same object as the one on the tab.
    var colour: JobColor = UserProfile.defaultColor

    private var logged: [Shift] { shifts.logged }
    private var totalEarnings: Double { logged.reduce(0) { $0 + $1.totalPay } }
    private var totalHours: Double { logged.reduce(0) { $0 + $1.hours } }
    private var totalTips: Double { logged.reduce(0) { $0 + $1.tipsAmount } }
    private var dayCount: Int { Set(logged.map(\.day)).count }

    private func earnings(of job: Job) -> Double {
        logged.filter { $0.job?.id == job.id }.reduce(0) { $0 + $1.totalPay }
    }

    /// The first day you logged, which is a truer "since" than the day the
    /// app was installed.
    private var since: Date {
        logged.map(\.checkIn).min() ?? UserProfile.started
    }

    private var tracksTips: Bool { jobs.contains(where: \.tracksTips) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Eyebrow("Total earned", opacity: 1)
                    .foregroundStyle(colour.color)
                Text(Fmt.money(totalEarnings))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("since \(Fmt.monthTitle(since))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // The same bar as the outlook card, split by job instead of by
            // certainty — so two cards that both break a total down break it
            // down the same way.
            if jobs.count > 1 && totalEarnings > 0 {
                ProportionBar(parts: jobs.map {
                    .init(value: earnings(of: $0), colour: $0.tint, style: .solid)
                })

                VStack(spacing: 8) {
                    ForEach(jobs) { job in
                        HStack(spacing: 8) {
                            Circle().fill(job.tint).frame(width: 7, height: 7)
                            Text(job.displayName).font(.subheadline)
                            Spacer(minLength: 8)
                            Text(Fmt.money(earnings(of: job)))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(job.tint)
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 0) {
                figure("Hours", Fmt.hours(totalHours))
                figure("Days", "\(dayCount)")
                if tracksTips {
                    figure("Tips", Fmt.money(totalTips))
                } else {
                    figure("Per day", Fmt.hours(dayCount == 0 ? 0 : totalHours / Double(dayCount)))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous)
                        .fill(LinearGradient(colors: [colour.color.opacity(0.10), .clear],
                                             startPoint: .top, endPoint: .bottom))
                }
        }
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProfileAvatar: View {
    let emoji: String
    let name: String
    var color: JobColor = UserProfile.defaultColor
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
                    Text("Your colour tints the Profile tab, the way a job's colour tints its own.")
                }

                if !allShifts.isEmpty {
                    Section {
                        AllTimeCard(jobs: jobs, shifts: allShifts, colour: color)
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
                    Button { colorRaw = option.rawValue } label: {
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
    @AppStorage(UserProfile.colorKey) private var colorRaw = UserProfile.defaultColor.rawValue

    private var accent: Color {
        (JobColor(rawValue: colorRaw) ?? UserProfile.defaultColor).color
    }

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
        .tint(accent)
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

struct JobProjection: View {
    let job: Job
    let shifts: [Shift]
    /// Your colour, for the control on the card. The card itself is the job's.
    var accent: Color = Palette.brand

    @AppStorage private var basisRaw: String

    init(job: Job, shifts: [Shift], accent: Color = Palette.brand) {
        self.job = job
        self.shifts = shifts
        self.accent = accent
        let fallback: ProjectionBasis = .pattern
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
            basis: basis,
            accent: accent
        )
    }
}

// MARK: - Your profile

/// Your emoji, or your initials when there's no emoji, on your colour.
