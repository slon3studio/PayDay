import SwiftUI
import SwiftData
import Charts

/// Everything combined: hours and earnings per job and across both.
struct ProfileView: View {
    @Query(sort: \Shift.checkIn, order: .reverse) private var allShifts: [Shift]

    @State private var scope: StatsScope = .allTime
    @State private var granularity: Granularity = .month
    @State private var metric: ProfileMetric = .hours

    enum Granularity: String, CaseIterable, Identifiable {
        case week = "Weekly"
        case month = "Monthly"

        var id: String { rawValue }
        var component: Calendar.Component { self == .week ? .weekOfYear : .month }
        var limit: Int { self == .week ? 8 : 6 }
    }

    private var scoped: [Shift] {
        StatsEngine.shifts(allShifts, in: scope)
    }

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
                        description: Text("Log shifts in the IJS or Maček tabs and your combined totals show up here.")
                    )
                } else {
                    content
                }
            }
            .navigationTitle("Profile")
        }
    }

    private var content: some View {
        List {
            Section {
                Picker("Scope", selection: $scope.animation(.default)) {
                    ForEach(StatsScope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)

                combinedCard
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            Section("Breakdown") {
                ForEach(Job.allCases) { job in
                    jobBreakdown(job)
                }
            }

            Section {
                comparisonChart
            } header: {
                Text("Compare")
            } footer: {
                Text("Both jobs side by side over the last \(granularity.limit) \(granularity == .week ? "weeks" : "months").")
            }

            Section {
                ForEach(Job.allCases) { job in
                    GoalRow(job: job)
                }
            } header: {
                Text("Monthly goals")
            } footer: {
                Text("Shown as progress on each job's projection card. Leave blank for no goal.")
            }

            Section("Rates") {
                ForEach(Job.allCases) { job in
                    HStack {
                        Label {
                            Text(job.displayName)
                        } icon: {
                            Image(systemName: job.symbol).foregroundStyle(job.tint)
                        }
                        Spacer()
                        Text("\(Fmt.money(job.hourlyRate))/h")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .dismissesKeyboardOnTap()
    }

    // MARK: - Cards

    private var combinedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total earned \(scope == .month ? "this month" : "all time")")
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
                StatTile(title: "Total hours", value: Fmt.hours(combinedHours), caption: "\(combinedDays) day\(combinedDays == 1 ? "" : "s") worked")
                StatTile(title: "Tips", value: Fmt.money(combinedTips), caption: "Maček only")
                StatTile(title: Job.ijs.displayName, value: Fmt.hours(stats(.ijs).totalHours), caption: Fmt.money(stats(.ijs).totalEarnings), tint: Job.ijs.tint)
                StatTile(title: Job.macek.displayName, value: Fmt.hours(stats(.macek).totalHours), caption: Fmt.money(stats(.macek).totalEarnings), tint: Job.macek.tint)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func jobBreakdown(_ job: Job) -> some View {
        let s = stats(job)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: job.symbol)
                    .foregroundStyle(job.tint)
                Text(job.displayName)
                    .font(.headline)
                Text(job.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            StatRow(label: "Hours", value: Fmt.hours(s.totalHours))
            StatRow(label: "Base pay", value: Fmt.money(s.basePay))
            if job.tracksTips {
                StatRow(label: "Tips", value: Fmt.money(s.totalTips))
            }
            StatRow(label: "Total", value: Fmt.money(s.totalEarnings), emphasized: true, tint: job.tint)
            StatRow(label: "Days · avg/day", value: "\(s.dayCount) · \(Fmt.hours(s.averageHoursPerDay))")
        }
        .padding(.vertical, 4)
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

#Preview {
    ProfileView()
        .modelContainer(PreviewData.container)
}
