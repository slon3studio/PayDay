import SwiftUI
import SwiftData
import Charts

/// Where this month is heading for each job, everything combined all time,
/// and the two jobs side by side. "This month so far" lives on each job's tab.
struct ProfileView: View {
    @Query(sort: \Shift.checkIn, order: .reverse) private var allShifts: [Shift]

    @State private var granularity: Granularity = .month
    @State private var metric: ProfileMetric = .hours
    @State private var showingSettings = false

    enum Granularity: String, CaseIterable, Identifiable {
        case week = "Weekly"
        case month = "Monthly"

        var id: String { rawValue }
        var component: Calendar.Component { self == .week ? .weekOfYear : .month }
        var limit: Int { self == .week ? 8 : 6 }
    }

    private var scoped: [Shift] { allShifts }

    private func stats(_ job: Job) -> ShiftStats {
        ShiftStats(job: job, shifts: scoped.filter { $0.job == job })
    }

    private var combinedHours: Double { scoped.reduce(0) { $0 + $1.hours } }
    private var combinedEarnings: Double { scoped.reduce(0) { $0 + $1.totalPay } }
    private var combinedTips: Double { scoped.reduce(0) { $0 + $1.tipsAmount } }
    private var combinedDays: Int { Set(scoped.map(\.day)).count }

    private var buckets: [StatsEngine.Bucket] {
        StatsEngine.buckets(from: allShifts, granularity: granularity.component, limit: granularity.limit)
    }

    var body: some View {
        NavigationStack {
            Group {
                if allShifts.isEmpty {
                    ContentUnavailableView(
                        "Nothing logged yet",
                        systemImage: "chart.bar.doc.horizontal",
                        description: Text("Log shifts in the \(Job.ijs.displayName) or \(Job.macek.displayName) tabs and your combined totals show up here.")
                    )
                } else {
                    content
                }
            }
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
        }
    }

    private var content: some View {
        List {
            Section {
                ForEach(Job.allCases) { job in
                    JobProjection(job: job, shifts: allShifts.filter { $0.job == job })
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } header: {
                Text("Projected pay · \(Fmt.monthTitle(.now))")
            }

            Section {
                combinedCard
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            } header: {
                Text("All time")
            }

            Section {
                comparisonChart
            } header: {
                Text("Compare")
            } footer: {
                Text("Both jobs side by side over the last \(granularity.limit) \(granularity == .week ? "weeks" : "months").")
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Cards

    private var combinedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total earned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Fmt.money(combinedEarnings))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(.green)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }

            StatGrid {
                StatTile(
                    title: "Total hours",
                    value: Fmt.hours(combinedHours),
                    caption: "\(Fmt.count(combinedDays, "day")) · \(Fmt.count(scoped.count, "shift"))",
                    background: Color(.tertiarySystemFill)
                )
                StatTile(
                    title: "Tips",
                    value: Fmt.money(combinedTips),
                    caption: "\(Job.macek.displayName) only",
                    background: Color(.tertiarySystemFill)
                )
                ForEach(Job.allCases) { job in
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var comparisonChart: some View {
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
                    ForEach(Job.allCases) { job in
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
            .chartForegroundStyleScale([
                Job.ijs.displayName: Job.ijs.tint,
                Job.macek.displayName: Job.macek.tint
            ])
            .chartLegend(position: .bottom)
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
        _basisRaw = AppStorage(wrappedValue: fallback.rawValue, "projectionBasis.\(job.rawValue)")
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

// MARK: - Settings

/// Light or dark, or whatever the phone is set to.
enum Appearance: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    static let key = "appearance"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Everything you set once and then leave alone: theme, and per job the rate,
/// goal and the times a new shift starts with.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Appearance.key) private var appearanceRaw: String = Appearance.system.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearanceRaw) {
                        ForEach(Appearance.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }

                ForEach(Job.allCases) { job in
                    JobSettingsSection(job: job)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneButton()
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

/// One job's settings: hourly rate, monthly goal, and its usual shift times.
private struct JobSettingsSection: View {
    let job: Job

    @AppStorage private var savedRate: Double
    @AppStorage private var checkInMinutes: Int
    @AppStorage private var checkOutMinutes: Int
    @State private var rateText: String

    init(job: Job) {
        self.job = job
        _savedRate = AppStorage(wrappedValue: 0, job.hourlyRateKey)
        _checkInMinutes = AppStorage(wrappedValue: job.standardCheckInMinutes, job.defaultCheckInKey)
        _checkOutMinutes = AppStorage(wrappedValue: job.standardCheckOutMinutes, job.defaultCheckOutKey)
        _rateText = State(initialValue: String(format: "%.2f", job.hourlyRate))
    }

    var body: some View {
        Section {
            HStack {
                Text("Hourly rate")
                Spacer()
                TextField("0.00", text: $rateText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 90)
                    .onChange(of: rateText) { _, new in
                        let value = Double(new.replacingOccurrences(of: ",", with: ".")) ?? 0
                        if value > 0 { savedRate = value }
                    }
                Text("€/h").foregroundStyle(.secondary)
            }

            GoalRow(job: job)

            DatePicker("New shift starts", selection: timeBinding($checkInMinutes), displayedComponents: .hourAndMinute)
            DatePicker("New shift ends", selection: timeBinding($checkOutMinutes), displayedComponents: .hourAndMinute)
        } header: {
            Label(job.displayName, systemImage: job.symbol)
                .foregroundStyle(job.tint)
        } footer: {
            Text("A new rate applies to shifts you log from now on — ones already logged keep theirs. Leave the goal blank for none.")
        }
        .tint(job.tint)
    }

    /// Minutes past midnight, as a `Date` today for the time picker.
    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: minutes.wrappedValue / 60,
                    minute: minutes.wrappedValue % 60,
                    second: 0,
                    of: .now
                ) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}

#Preview {
    ProfileView()
        .modelContainer(PreviewData.container)
}
